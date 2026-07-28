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
TerminalApi apiReturning(List<Map<String, dynamic>> Function() orders,
    {List<String> log = const []}) {
  final client = MockClient((req) async {
    if (req.url.path.endsWith('/ack')) {
      (log as List<String>).add(req.url.path);
      return http.Response('{"changed":true}', 200);
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
