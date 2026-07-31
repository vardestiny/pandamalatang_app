import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pandamalatang_terminal/l10n/app_localizations.dart';
import 'package:pandamalatang_terminal/src/api/terminal_api.dart';
import 'package:pandamalatang_terminal/src/screens/history_screen.dart';
import 'package:pandamalatang_terminal/src/services/order_poller.dart';
import 'package:pandamalatang_terminal/src/theme.dart';

/// Today's orders. The board drops an order at handover, so this is the only place
/// a finished one can still be looked up — which makes "did it load, and is the
/// total right" the whole of what matters here.

Map<String, dynamic> historyOrder(
  int id,
  String reference,
  String status,
  double total,
) => {
      'id': id,
      'reference': reference,
      'status': status,
      'source': 'ONLINE',
      'createdAt': DateTime.now().toIso8601String(),
      'pickupTime': null,
      'customerName': 'Test',
      'customerPhone': null,
      'notes': null,
      'totalAmount': total,
      'drinks': [
        {'name': 'Assam Milchtee', 'size': '700 ml', 'quantity': 1, 'lineTotal': total},
      ],
      'bowls': const [],
    };

/// A poller whose history endpoint answers with [body], or fails when null.
OrderPoller pollerReturning(Map<String, dynamic>? body, {List<String>? log}) {
  final client = MockClient((req) async {
    log?.add(req.url.path);
    if (req.url.path.endsWith('/history')) {
      if (body == null) return http.Response('nope', 500);
      return http.Response(jsonEncode(body), 200);
    }
    // The board's own poll, which the history screen must not trigger.
    return http.Response('{"orders":[],"terminal":{"name":"Theke"}}', 200);
  });
  return OrderPoller(
    api: TerminalApi(baseUrl: 'https://x.test', token: 't', client: client),
  );
}

Future<void> pumpHistory(
  WidgetTester tester,
  OrderPoller poller, {
  String locale = 'de',
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: pandaTheme(),
    locale: Locale(locale),
    localizationsDelegates: L.localizationsDelegates,
    supportedLocales: L.supportedLocales,
    // A fresh key per pump, so a second call in one test builds a new State and
    // fetches again. Without it Flutter reuses the element, `initState` never
    // re-runs, and the screen keeps the first call's data — which makes a test
    // that pumps twice pass while asserting nothing.
    home: HistoryScreen(key: UniqueKey(), poller: poller),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists today\'s orders with the day\'s takings', (tester) async {
    await pumpHistory(
      tester,
      pollerReturning({
        'truncated': false,
        'summary': {'orders': 2, 'cancelled': 0, 'total': 24.7},
        'orders': [
          historyOrder(3, 'K7F2QM', 'COMPLETED', 19.4),
          historyOrder(2, 'B4XT9P', 'COMPLETED', 5.3),
        ],
      }),
    );

    expect(find.text('#K7F2QM'), findsOneWidget);
    expect(find.text('#B4XT9P'), findsOneWidget);
    expect(find.text('2 Bestellungen'), findsOneWidget);
    expect(find.textContaining('24,70'), findsOneWidget);
  });

  testWidgets('a finished order offers no step button', (tester) async {
    // The card is read-only because it is given no callback. A handed-over order
    // must not present a button that would walk it somewhere.
    await pumpHistory(
      tester,
      pollerReturning({
        'summary': {'orders': 1, 'cancelled': 0, 'total': 5.3},
        'orders': [historyOrder(1, 'K7F2QM', 'COMPLETED', 5.3)],
      }),
    );

    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('says how many were cancelled, and only when some were',
      (tester) async {
    // The line exists to explain why the total is lower than the list looks. A
    // permanent "0 storniert" would be noise.
    await pumpHistory(
      tester,
      pollerReturning({
        'summary': {'orders': 1, 'cancelled': 1, 'total': 5.3},
        'orders': [
          historyOrder(2, 'K7F2QM', 'CANCELLED', 8.0),
          historyOrder(1, 'B4XT9P', 'COMPLETED', 5.3),
        ],
      }),
    );
    expect(find.text('1 storniert'), findsOneWidget);

    await pumpHistory(
      tester,
      pollerReturning({
        'summary': {'orders': 1, 'cancelled': 0, 'total': 5.3},
        'orders': [historyOrder(1, 'B4XT9P', 'COMPLETED', 5.3)],
      }),
    );
    expect(find.textContaining('storniert'), findsNothing);
  });

  testWidgets('an empty day says so rather than showing a blank screen',
      (tester) async {
    await pumpHistory(
      tester,
      pollerReturning({
        'summary': {'orders': 0, 'cancelled': 0, 'total': 0},
        'orders': const [],
      }),
    );
    expect(find.text('Heute noch keine Bestellungen.'), findsOneWidget);
  });

  testWidgets('a failed load says so and offers a retry', (tester) async {
    // Not a silent blank: the board behind this screen is still live, and a staff
    // member needs to know this list is missing rather than empty.
    final log = <String>[];
    await pumpHistory(tester, pollerReturning(null, log: log));

    expect(find.text('Bestellungen konnten nicht geladen werden.'), findsOneWidget);
    final before = log.length;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(log.length, greaterThan(before));
  });

  testWidgets('warns when the server capped the list', (tester) async {
    // A list that quietly stops reads as "that was the whole day".
    await pumpHistory(
      tester,
      pollerReturning({
        'truncated': true,
        'summary': {'orders': 200, 'cancelled': 0, 'total': 1000},
        'orders': [historyOrder(1, 'K7F2QM', 'COMPLETED', 5.0)],
      }),
    );
    expect(find.textContaining('200'), findsWidgets);
  });

  testWidgets('reads in all three languages', (tester) async {
    for (final (locale, empty) in const [
      ('de', 'Heute noch keine Bestellungen.'),
      ('en', 'No orders yet today.'),
      ('zh', '今天还没有订单。'),
    ]) {
      await pumpHistory(
        tester,
        pollerReturning({
          'summary': {'orders': 0, 'cancelled': 0, 'total': 0},
          'orders': const [],
        }),
        locale: locale,
      );
      expect(find.text(empty), findsOneWidget, reason: 'empty state in $locale');
    }
  });
}
