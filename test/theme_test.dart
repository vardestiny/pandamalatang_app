import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandamalatang_terminal/l10n/app_localizations.dart';
import 'package:pandamalatang_terminal/src/models/order.dart';
import 'package:pandamalatang_terminal/src/theme.dart';
import 'package:pandamalatang_terminal/src/widgets/order_card.dart';

/// These exist because of a crash that reached a real device: `pandaTheme()`
/// called `textTheme.apply(fontSizeFactor: 1.1)`, and every `fontSize` in
/// `ThemeData.textTheme` is null until Flutter merges the locale's script
/// geometry in later — so it asserted the moment the app built its theme.
///
/// Nothing in the suite built a theme or rendered a widget, so `analyze` and the
/// poller tests were green while the app could not start at all. That gap is the
/// point of this file.
void main() {
  final stock = ThemeData.light(useMaterial3: true);

  test('the theme can be built at all', () {
    expect(pandaTheme, returnsNormally);
  });

  testWidgets("text is scaled up for arm's-length reading", (tester) async {
    late TextTheme resolved;
    await tester.pumpWidget(MaterialApp(
      theme: pandaTheme(),
      home: Builder(builder: (context) {
        resolved = Theme.of(context).textTheme;
        return const SizedBox();
      }),
    ));

    // Compared against the stock *geometry* rather than a second pumped theme:
    // two themes in one pump share a localisation cache and quietly report the
    // same numbers, which is how an earlier version of this test passed a broken
    // theme. Ratios rather than hard-coded points, so retuning M3 upstream does
    // not fail the build.
    final stockBody = stock.typography.englishLike.bodyMedium!.fontSize!;
    final stockHead = stock.typography.englishLike.headlineLarge!.fontSize!;
    expect(resolved.bodyMedium!.fontSize! / stockBody, closeTo(1.1, 0.001));
    expect(resolved.headlineLarge!.fontSize! / stockHead, closeTo(1.1, 0.001));

    // The colour half of the theme has to survive the fix that moved scaling off
    // `textTheme`; ink-on-cream is the shop's palette, not Material's grey.
    expect(resolved.bodyMedium!.color, PandaColors.ink);
  });

  test('every script geometry is scaled, not just englishLike', () {
    final scaled = pandaTheme().typography;
    for (final (name, got, want) in [
      ('englishLike', scaled.englishLike, stock.typography.englishLike),
      ('dense', scaled.dense, stock.typography.dense),
      ('tall', scaled.tall, stock.typography.tall),
    ]) {
      expect(got.bodyMedium!.fontSize! / want.bodyMedium!.fontSize!,
          closeTo(1.1, 0.001),
          reason: '$name geometry was left at stock size');
    }
  });

  testWidgets('an order card renders under the real theme', (tester) async {
    final order = TerminalOrder.fromJson({
      'id': 1042,
      'status': 'PENDING',
      'source': 'ONLINE',
      'createdAt': DateTime.now().toIso8601String(),
      'pickupTime':
          DateTime.now().add(const Duration(minutes: 25)).toIso8601String(),
      'customerName': 'Wenbiao Peng',
      'customerPhone': '012345678',
      'totalAmount': 26.4,
      'drinks': [
        {
          'name': 'Assam Milchtee + Tapioka',
          'quantity': 2,
          'options': ['700 ml', 'Perlen', 'Käsecreme'],
          'lineTotal': 9.4,
        },
      ],
      'bowls': [
        {
          'amount': 15.0,
          'targetWeightG': 500,
          'soupBase': 'Mala',
          'spiceLevel': 'MEDIUM',
          'boil': ['Rindfleisch', 'Tofu', 'Enoki'],
          'toppings': ['Knoblauch', 'Sesam'],
          'exclude': ['Koriander'],
          'note': 'Extra scharf bitte',
        },
      ],
    });

    await tester.pumpWidget(MaterialApp(
      theme: pandaTheme(),
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(child: OrderCardView(order: order)),
      ),
    ));

    expect(tester.takeException(), isNull);
    expect(find.textContaining('1042'), findsOneWidget);
    // The allergy line has to reach the screen; it is the one with consequences.
    expect(find.textContaining('Koriander'), findsOneWidget);
  });
}
