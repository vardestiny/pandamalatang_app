import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandamalatang_terminal/l10n/app_localizations.dart';
import 'package:pandamalatang_terminal/src/l10n_ext.dart';
import 'package:pandamalatang_terminal/src/models/order.dart';

/// The tablet renders `preparation`, so this is what staff actually read off the
/// screen when they make the cup.
void main() {
  OrderDrink drink(Map<String, dynamic> extra) => OrderDrink.fromJson({
        'name': 'Assam Milchtee',
        'quantity': 1,
        'options': <String>[],
        'lineTotal': 4.4,
        ...extra,
      });

  late L de;
  late L en;
  late L zh;

  setUpAll(() async {
    de = await L.delegate.load(const Locale('de'));
    en = await L.delegate.load(const Locale('en'));
    zh = await L.delegate.load(const Locale('zh'));
  });

  test('temperature comes first — it decides which jug', () {
    final iced = drink({'sugarLevel': 'HALF', 'temperature': 'ICED'});
    expect(zh.preparation(iced), '加冰 · 五分糖');
    expect(de.preparation(iced), 'Mit Eis · 50 %');
    expect(en.preparation(iced), 'Iced · 50%');
  });

  test('either one alone still prints', () {
    expect(zh.preparation(drink({'temperature': 'HOT'})), '热');
    expect(zh.preparation(drink({'sugarLevel': 'FULL'})), '全糖');
    expect(de.preparation(drink({'temperature': 'HOT'})), 'Heiß');
  });

  test('a side dish shows nothing rather than an empty separator', () {
    expect(zh.preparation(drink({})), isNull);
    expect(
      zh.preparation(drink({'sugarLevel': null, 'temperature': null})),
      isNull,
    );
  });

  test('an unknown value is dropped, not printed raw', () {
    // A level added on the server before the tablet is updated must not put
    // "LUKEWARM" on a ticket.
    expect(zh.preparation(drink({'temperature': 'LUKEWARM'})), isNull);
    expect(
      zh.preparation(drink({'temperature': 'HOT', 'sugarLevel': 'QUARTER'})),
      '热',
    );
  });

  test('a status the tablet has never heard of is shown, not swallowed', () {
    // An unlabelled card is still a real order; a blank one is a lost one.
    expect(de.statusBadge('TELEPORTED'), 'TELEPORTED');
    expect(en.statusName('TELEPORTED'), 'TELEPORTED');
  });

  test('money is placed the way the reader places it', () {
    // German puts the symbol last, behind a non-breaking space, so the amount
    // and the € never wrap apart on a narrow card.
    expect(de.money(15), '15,00 €');
    expect(en.money(15), '€15.00');
  });

  test('pickup times stay 24-hour in every language', () {
    // The web console is fixed at 24-hour too. An am/pm slip on a pickup time
    // is an order handed over an hour late.
    final at = DateTime(2026, 7, 29, 18, 30);
    for (final l in [de, en, zh]) {
      expect(l.pickupAt(at), '18:30');
    }
  });
}
