/// Wire models for the terminal order feed.
///
/// Hand-written rather than generated: there are three shapes, they change with
/// the backend in the same commit, and a build_runner step for this would cost
/// more than it saves.
class TerminalOrder {
  const TerminalOrder({
    required this.id,
    required this.status,
    required this.source,
    required this.createdAt,
    required this.pickupTime,
    required this.customerName,
    required this.customerPhone,
    required this.notes,
    required this.totalAmount,
    required this.drinks,
    required this.bowls,
  });

  final int id;
  final String status;
  final String source;
  final DateTime createdAt;
  final DateTime? pickupTime;
  final String? customerName;
  final String? customerPhone;
  final String? notes;
  final double totalAmount;
  final List<OrderDrink> drinks;
  final List<OrderBowl> bowls;

  /// Not yet accepted by anyone — the state that makes the alarm ring.
  bool get isNew => status == 'PENDING';

  static DateTime? _date(Object? v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;

  factory TerminalOrder.fromJson(Map<String, dynamic> j) => TerminalOrder(
        id: j['id'] as int,
        status: j['status'] as String? ?? 'PENDING',
        source: j['source'] as String? ?? 'ONLINE',
        // The feed always sends createdAt; falling back to "now" keeps a
        // malformed row visible on the board instead of crashing the poll and
        // taking every other order down with it.
        createdAt: _date(j['createdAt']) ?? DateTime.now(),
        pickupTime: _date(j['pickupTime']),
        customerName: j['customerName'] as String?,
        customerPhone: j['customerPhone'] as String?,
        notes: j['notes'] as String?,
        totalAmount: (j['totalAmount'] as num?)?.toDouble() ?? 0,
        drinks: (j['drinks'] as List<dynamic>? ?? const [])
            .map((e) => OrderDrink.fromJson(e as Map<String, dynamic>))
            .toList(),
        bowls: (j['bowls'] as List<dynamic>? ?? const [])
            .map((e) => OrderBowl.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class OrderDrink {
  const OrderDrink({
    required this.name,
    required this.quantity,
    required this.options,
    required this.lineTotal,
    this.sugarLevel,
    this.temperature,
  });

  final String name;
  final int quantity;

  /// Paid add-ons. Part of the prep instruction, not a price footnote: a tea
  /// with cheese cream is different work from one without.
  final List<String> options;
  final double lineTotal;

  /// 糖度 / 冷热, as the server's enum names — the labels below are the app's, so
  /// the tablet reads in its own language rather than whatever the website sent.
  /// Null for a side dish, and for any line taken before the choice existed.
  final String? sugarLevel;
  final String? temperature;

  static const _sugar = {'HALF': '五分糖', 'FULL': '全糖'};
  static const _temp = {'HOT': '热', 'ROOM': '常温', 'ICED': '加冰'};

  /// How to make it, ready to print — temperature first, since that decides
  /// which jug it comes out of.
  String? get preparation {
    final parts = [
      _temp[temperature ?? ''],
      _sugar[sugarLevel ?? ''],
    ].whereType<String>().toList();
    return parts.isEmpty ? null : parts.join(' · ');
  }

  factory OrderDrink.fromJson(Map<String, dynamic> j) => OrderDrink(
        name: j['name'] as String? ?? '?',
        quantity: j['quantity'] as int? ?? 1,
        options: (j['options'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
        lineTotal: (j['lineTotal'] as num?)?.toDouble() ?? 0,
        sugarLevel: j['sugarLevel'] as String?,
        temperature: j['temperature'] as String?,
      );
}

class OrderBowl {
  const OrderBowl({
    required this.amount,
    required this.targetWeightG,
    required this.soupBase,
    required this.spiceLevel,
    required this.boil,
    required this.toppings,
    required this.exclude,
    required this.note,
  });

  final double amount;
  final int targetWeightG;
  final String soupBase;
  final String? spiceLevel;
  final List<String> boil;
  final List<String> toppings;

  /// Where allergies live. Rendered in red, always, never truncated.
  final List<String> exclude;
  final String? note;

  static List<String> _strings(Object? v) =>
      (v as List<dynamic>? ?? const []).map((e) => e.toString()).toList();

  factory OrderBowl.fromJson(Map<String, dynamic> j) => OrderBowl(
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        targetWeightG: j['targetWeightG'] as int? ?? 0,
        soupBase: j['soupBase'] as String? ?? '?',
        spiceLevel: j['spiceLevel'] as String?,
        boil: _strings(j['boil']),
        toppings: _strings(j['toppings']),
        exclude: _strings(j['exclude']),
        note: j['note'] as String?,
      );
}

class OrderFeed {
  const OrderFeed({required this.orders, required this.terminalName});
  final List<TerminalOrder> orders;
  final String terminalName;

  factory OrderFeed.fromJson(Map<String, dynamic> j) => OrderFeed(
        terminalName: (j['terminal'] as Map<String, dynamic>?)?['name'] as String? ?? '',
        orders: (j['orders'] as List<dynamic>? ?? const [])
            .map((e) => TerminalOrder.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
