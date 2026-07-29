import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pandamalatang_terminal/src/api/terminal_api.dart';
import 'package:pandamalatang_terminal/src/services/order_poller.dart';

Map<String, dynamic> order(int id, {String status = 'PENDING'}) => {
      'id': id,
      'status': status,
      'source': 'ONLINE',
      'createdAt': DateTime.now().toIso8601String(),
      'pickupTime': null,
      'customerName': 'Test',
      'customerPhone': null,
      'notes': null,
      'totalAmount': 4.3,
      'drinks': [
        {'name': 'Assam Milk Tea', 'quantity': 2, 'options': ['Perlen'], 'lineTotal': 9.6},
      ],
      'bowls': const [],
    };

/// A feed whose contents the test controls between polls.
///
/// [onStatus] answers the step endpoint. Returning null makes it fail, which is
/// how the offline cases are written.
TerminalApi apiReturning(
  List<Map<String, dynamic>> Function() orders, {
  // Growable, and nullable rather than defaulted: a `const []` here would throw
  // inside the handler on the first add, and the client swallows that as a
  // failed request — which is a confusing way to find out about a typo.
  List<String>? log,
  String? Function(int id, String status)? onStatus,
}) {
  final client = MockClient((req) async {
    if (req.url.path.endsWith('/ack')) {
      log?.add(req.url.path);
      return http.Response('{"changed":true}', 200);
    }
    if (req.url.path.endsWith('/status')) {
      final id = int.parse(req.url.pathSegments[
          req.url.pathSegments.indexOf('orders') + 1]);
      final asked = (jsonDecode(req.body) as Map<String, dynamic>)['status'] as String;
      log?.add('$id→$asked');
      final settled = onStatus == null ? asked : onStatus(id, asked);
      if (settled == null) return http.Response('boom', 500);
      // The API answers a refusal with where the order really is, under a 409.
      return http.Response(
        jsonEncode({'id': id, 'status': settled}),
        settled == asked ? 200 : 409,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response(
      jsonEncode({
        'serverTime': DateTime.now().toIso8601String(),
        'terminal': {'id': 1, 'name': 'Theke'},
        'orders': orders(),
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
  return TerminalApi(baseUrl: 'https://x', token: 't', client: client);
}

String statusOf(OrderPoller p, int id) =>
    p.orders.firstWhere((o) => o.id == id).status;

void main() {
  test('the first poll does not alarm for orders that were already open', () async {
    // Otherwise every app restart alarms for the whole board, and staff learn to
    // ignore the alarm — which defeats the entire app.
    final poller = OrderPoller(api: apiReturning(() => [order(1), order(2)]));
    await poller.poll();

    expect(poller.orders, hasLength(2));
    expect(poller.pending, isEmpty);
  });

  test('an order arriving after the first poll does alarm', () async {
    var feed = [order(1)];
    final poller = OrderPoller(api: apiReturning(() => feed));
    await poller.poll();
    expect(poller.pending, isEmpty);

    feed = [order(1), order(2)];
    await poller.poll();

    expect(poller.pending.map((o) => o.id), [2]);
  });

  test('an order already accepted elsewhere never alarms', () async {
    var feed = [order(1)];
    final poller = OrderPoller(api: apiReturning(() => feed));
    await poller.poll();

    feed = [order(1), order(9, status: 'PREPARING')];
    await poller.poll();

    expect(poller.pending, isEmpty);
  });

  test('accepting on the web console clears the alarm here too', () async {
    // The alarm must not outlive the reason for it: someone dealt with the order
    // on the other screen, so the noise has to stop without a second human.
    var feed = [order(1)];
    final poller = OrderPoller(api: apiReturning(() => feed));
    await poller.poll();

    feed = [order(1), order(2)];
    await poller.poll();
    expect(poller.pending, hasLength(1));

    feed = [order(1), order(2, status: 'CONFIRMED')];
    await poller.poll();
    expect(poller.pending, isEmpty);
  });

  test('an order vanishing from the feed clears its alarm', () async {
    // Cancelled from the console: the feed drops it, and an alarm for an order
    // that no longer exists can never be silenced by accepting it.
    var feed = [order(1)];
    final poller = OrderPoller(api: apiReturning(() => feed));
    await poller.poll();

    feed = [order(1), order(3)];
    await poller.poll();
    expect(poller.pending, hasLength(1));

    feed = [order(1)];
    await poller.poll();
    expect(poller.pending, isEmpty);
  });

  test('acknowledging silences immediately, before the network round-trip', () async {
    var feed = [order(1)];
    final poller = OrderPoller(api: apiReturning(() => feed));
    await poller.poll();
    feed = [order(1), order(2)];
    await poller.poll();

    // The staff member has seen the order; the noise should stop on the tap, not
    // when the server gets round to answering.
    feed = [order(1), order(2, status: 'CONFIRMED')];
    await poller.acknowledge(2);

    expect(poller.pending, isEmpty);
  });

  test('a step shows on the card before the server has answered', () async {
    // The poll is every ten seconds. A card that sits unchanged for most of that
    // after a tap reads as a dead button, and the second tap it invites is a
    // step skipped rather than a step repeated.
    var feed = [order(1, status: 'CONFIRMED')];
    final poller = OrderPoller(
      api: apiReturning(() => feed, onStatus: (_, s) => s),
    );
    await poller.poll();

    // The feed deliberately still says CONFIRMED — this is the window between
    // the tap and the server catching up.
    final settled = await poller.advance(1, 'PREPARING');

    expect(settled, 'PREPARING');
    expect(statusOf(poller, 1), 'PREPARING');
  });

  test('the local step gives way once the feed agrees', () async {
    var feed = [order(1, status: 'CONFIRMED')];
    final poller = OrderPoller(api: apiReturning(() => feed));
    await poller.poll();
    await poller.advance(1, 'PREPARING');

    feed = [order(1, status: 'READY')];
    await poller.poll();

    // Someone finished it on the console. The board follows the server, not the
    // tap it is still holding.
    expect(statusOf(poller, 1), 'READY');
  });

  test('a step that did not reach the server is taken back off the card', () async {
    // Unlike silencing the alarm, an unrecorded step must not look done: the
    // console, the kitchen and the next shift would all still show the order
    // where it was.
    var feed = [order(1, status: 'PREPARING')];
    final poller = OrderPoller(
      api: apiReturning(() => feed, onStatus: (_, _) => null),
    );
    await poller.poll();

    final settled = await poller.advance(1, 'READY');

    expect(settled, isNull);
    expect(statusOf(poller, 1), 'PREPARING');
  });

  test('a board a poll behind is corrected, not obeyed', () async {
    // Two tablets. This one still shows CONFIRMED and taps "Kochen"; the other
    // already marked the order ready. Forward-only, so the server refuses and
    // says where the order actually is.
    var feed = [order(1, status: 'CONFIRMED')];
    final poller = OrderPoller(
      api: apiReturning(() => feed, onStatus: (_, _) => 'READY'),
    );
    await poller.poll();

    feed = [order(1, status: 'READY')];
    final settled = await poller.advance(1, 'PREPARING');

    expect(settled, 'READY');
    expect(statusOf(poller, 1), 'READY');
  });

  test('handing over takes the order off the board', () async {
    var feed = [order(1, status: 'READY'), order(2, status: 'PREPARING')];
    final poller = OrderPoller(api: apiReturning(() => feed));
    await poller.poll();

    // COMPLETED leaves the feed — the server only sends what is still open.
    feed = [order(2, status: 'PREPARING')];
    await poller.advance(1, 'COMPLETED');

    expect(poller.orders.map((o) => o.id), [2]);
  });

  test('stepping a still-ringing order silences it too', () async {
    // Reachable when the alarm was acknowledged on the console: the overlay is
    // gone here, the card is back, and the tap on it must not leave the app
    // holding an alarm for an order already being cooked.
    var feed = [order(1)];
    final poller = OrderPoller(api: apiReturning(() => feed));
    await poller.poll();

    feed = [order(1), order(2)];
    await poller.poll();
    expect(poller.pending, hasLength(1));

    feed = [order(1), order(2, status: 'PREPARING')];
    await poller.advance(2, 'PREPARING');

    expect(poller.pending, isEmpty);
  });

  test('two consecutive failures count as offline', () async {
    // Silence from a terminal looks exactly like a quiet shop, so this drives a
    // visible banner rather than being swallowed.
    final client = MockClient((_) async => http.Response('nope', 500));
    final poller = OrderPoller(
      api: TerminalApi(baseUrl: 'https://x', token: 't', client: client),
    );

    await poller.poll();
    expect(poller.isOffline, isFalse);
    await poller.poll();
    expect(poller.isOffline, isTrue);
  });

  test('a 401 stops polling and asks for re-pairing', () async {
    // Distinct from a network failure: retrying a revoked token forever would
    // never recover, and unpairing over flaky wifi would be worse.
    final client = MockClient((_) async => http.Response('{}', 401));
    final poller = OrderPoller(
      api: TerminalApi(baseUrl: 'https://x', token: 'stale', client: client),
    );

    await poller.poll();

    expect(poller.unauthorized, isTrue);
    expect(poller.isOffline, isFalse);
  });

  test('a malformed order does not take the whole poll down with it', () async {
    final client = MockClient((_) async => http.Response(
          jsonEncode({
            'terminal': {'name': 'Theke'},
            'orders': [
              {'id': 5},
            ],
          }),
          200,
        ));
    final poller = OrderPoller(
      api: TerminalApi(baseUrl: 'https://x', token: 't', client: client),
    );

    await poller.poll();

    expect(poller.orders, hasLength(1));
    expect(poller.orders.first.drinks, isEmpty);
    expect(poller.consecutiveFailures, 0);
  });
}
