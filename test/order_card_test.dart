import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandamalatang_terminal/l10n/app_localizations.dart';
import 'package:pandamalatang_terminal/src/l10n_ext.dart';
import 'package:pandamalatang_terminal/src/models/order.dart';
import 'package:pandamalatang_terminal/src/theme.dart';
import 'package:pandamalatang_terminal/src/widgets/order_card.dart';

TerminalOrder orderAt(String status) => TerminalOrder.fromJson({
      'id': 1042,
      'reference': 'K7F2QM',
      'status': status,
      'source': 'ONLINE',
      'createdAt': DateTime.now().toIso8601String(),
      'totalAmount': 4.3,
      'drinks': [
        {
          'name': 'Assam Milchtee',
          'size': '700 ml',
          'quantity': 1,
          'lineTotal': 4.3,
        },
      ],
      'bowls': const [],
    });

Future<void> pumpCard(
  WidgetTester tester,
  TerminalOrder order, {
  Future<void> Function(String)? onAdvance,
  String locale = 'de',
}) =>
    tester.pumpWidget(MaterialApp(
      theme: pandaTheme(),
      locale: Locale(locale),
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: OrderCardView(order: order, onAdvance: onAdvance),
        ),
      ),
    ));

void main() {
  testWidgets('the card shows the customer\'s code, never the row id', (tester) async {
    // The whole point of the reference: the id is internal, and a padded id on
    // screen told anyone reading the board how many orders the shop had taken.
    await pumpCard(tester, orderAt('CONFIRMED'));

    expect(find.text('#K7F2QM'), findsOneWidget);
    expect(find.text('#1042'), findsNothing);
  });

  testWidgets('falls back to the id against a backend without the field',
      (tester) async {
    // An older server sends no `reference`. The card must still identify the
    // order rather than render a blank where the number goes.
    final legacy = TerminalOrder.fromJson({
      'id': 1042,
      'status': 'CONFIRMED',
      'source': 'ONLINE',
      'createdAt': DateTime.now().toIso8601String(),
      'totalAmount': 4.3,
      'drinks': const [],
      'bowls': const [],
    });
    await pumpCard(tester, legacy);

    expect(find.text('#1042'), findsOneWidget);
  });

  testWidgets('the cup size is on the drink line', (tester) async {
    // The regression this exists for: the size used to live in the drink's name,
    // and `strip-size-from-names` moved it into its own column for the website's
    // size toggle. The kitchen ticket had been reading it out of the name, so a
    // 500 ml and a 700 ml Assam silently became the same line.
    await pumpCard(tester, orderAt('CONFIRMED'));
    expect(find.text('700 ml'), findsOneWidget);
  });

  testWidgets('a one-size drink shows no size at all', (tester) async {
    // Most of the menu is sold in one size. A chip reading "null" or an empty box
    // would be worse than the omission.
    final single = TerminalOrder.fromJson({
      'id': 7,
      'reference': 'AAA111',
      'status': 'CONFIRMED',
      'createdAt': DateTime.now().toIso8601String(),
      'totalAmount': 4.3,
      'drinks': [
        {'name': 'Assam Milchtee', 'quantity': 1, 'lineTotal': 4.3},
      ],
      'bowls': const [],
    });
    await pumpCard(tester, single);

    expect(find.text('Assam Milchtee'), findsOneWidget);
    expect(find.textContaining('ml'), findsNothing);
  });

  testWidgets('the button names the step, in the console\'s words', (tester) async {
    for (final (status, label) in const [
      ('PENDING', 'Annehmen'),
      ('CONFIRMED', 'Kochen'),
      ('PREPARING', 'Fertig'),
      ('READY', 'Abgeholt'),
    ]) {
      await pumpCard(tester, orderAt(status), onAdvance: (_) async {});
      expect(find.text(label), findsOneWidget,
          reason: 'an order in $status should offer $label');
    }
  });

  testWidgets('tapping asks for the next status along the path', (tester) async {
    final asked = <String>[];
    await pumpCard(tester, orderAt('PREPARING'),
        onAdvance: (next) async => asked.add(next));

    await tester.tap(find.text('Fertig'));
    await tester.pump();

    expect(asked, ['READY']);
  });

  testWidgets('a second tap in the same spot is swallowed', (tester) async {
    // The button relabels itself the moment a step lands, so an impatient
    // double tap would otherwise land on the *next* step — two taps on "Fertig"
    // handing over an order still sitting on the counter.
    final asked = <String>[];
    await pumpCard(tester, orderAt('READY'),
        onAdvance: (next) async => asked.add(next));

    await tester.tap(find.text('Abgeholt'));
    await tester.pump();
    await tester.tap(find.text('Abgeholt'), warnIfMissed: false);
    await tester.pump();

    expect(asked, ['COMPLETED']);

    // And it comes back, so a step that genuinely needs repeating still can be.
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Abgeholt'));
    await tester.pump();
    expect(asked, ['COMPLETED', 'COMPLETED']);
  });

  testWidgets('a card with nowhere to go has no button', (tester) async {
    await pumpCard(tester, orderAt('COMPLETED'), onAdvance: (_) async {});
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('the same card reads in all three languages', (tester) async {
    // One order, one glance, three staff members. The words differ; the order
    // number, the quantity and the allergy warning must not.
    for (final (locale, step, badge) in const [
      ('de', 'Kochen', 'ANGENOMMEN'),
      ('en', 'Cook', 'ACCEPTED'),
      ('zh', '开始煮', '已接单'),
    ]) {
      await pumpCard(tester, orderAt('CONFIRMED'),
          onAdvance: (_) async {}, locale: locale);

      expect(find.text(step), findsOneWidget, reason: 'step button in $locale');
      expect(find.text(badge), findsOneWidget, reason: 'status chip in $locale');
      expect(find.text('#K7F2QM'), findsOneWidget,
          reason: 'the order code is the same string in every language');
    }
  });

  testWidgets('an allergy warning survives translation', (tester) async {
    final order = TerminalOrder.fromJson({
      'id': 7,
      'status': 'CONFIRMED',
      'createdAt': DateTime.now().toIso8601String(),
      'totalAmount': 15.0,
      'drinks': const [],
      'bowls': [
        {
          'amount': 15.0,
          'targetWeightG': 500,
          'soupBase': 'Mala',
          'spiceLevel': 'HOT',
          'exclude': ['Koriander'],
        },
      ],
    });

    for (final (locale, prefix, spice) in const [
      ('de', 'OHNE: Koriander', 'SEHR SCHARF'),
      ('en', 'WITHOUT: Koriander', 'EXTRA HOT'),
      ('zh', '不要：Koriander', '特辣'),
    ]) {
      await pumpCard(tester, order, onAdvance: (_) async {}, locale: locale);
      expect(find.text(prefix), findsOneWidget, reason: 'exclusion in $locale');
      expect(find.text(spice), findsOneWidget, reason: 'spice in $locale');
    }
  });

  testWidgets('dates format under every loaded locale', (tester) async {
    // `DateFormat` needs its locale's symbols loaded before it will format at
    // all. They arrive with the Material delegates rather than with the app's
    // own strings, so this only holds while the real delegate list is in use —
    // hence a widget test and not a unit one.
    for (final locale in const ['de', 'en', 'zh']) {
      late String rendered;
      await tester.pumpWidget(MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: L.localizationsDelegates,
        supportedLocales: L.supportedLocales,
        home: Builder(builder: (context) {
          rendered = L.of(context).date(DateTime(2026, 7, 29));
          return const SizedBox();
        }),
      ));
      expect(rendered, contains('2026'), reason: 'date in $locale');
    }
  });

  testWidgets('without a callback the card is read-only', (tester) async {
    // How a card is shown somewhere that must not offer a step of its own — the
    // alarm, for one, whose only way out is its own Annehmen button.
    await pumpCard(tester, orderAt('PENDING'));
    expect(find.text('Annehmen'), findsNothing);
  });
}
