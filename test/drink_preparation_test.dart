import 'package:flutter_test/flutter_test.dart';
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

  test('temperature comes first — it decides which jug', () {
    expect(drink({'sugarLevel': 'HALF', 'temperature': 'ICED'}).preparation,
        '加冰 · 五分糖');
  });

  test('either one alone still prints', () {
    expect(drink({'temperature': 'HOT'}).preparation, '热');
    expect(drink({'sugarLevel': 'FULL'}).preparation, '全糖');
  });

  test('a side dish shows nothing rather than an empty separator', () {
    expect(drink({}).preparation, isNull);
    expect(drink({'sugarLevel': null, 'temperature': null}).preparation, isNull);
  });

  test('an unknown value is dropped, not printed raw', () {
    // A level added on the server before the tablet is updated must not put
    // "LUKEWARM" on a ticket.
    expect(drink({'temperature': 'LUKEWARM'}).preparation, isNull);
    expect(drink({'temperature': 'HOT', 'sugarLevel': 'QUARTER'}).preparation, '热');
  });
}
