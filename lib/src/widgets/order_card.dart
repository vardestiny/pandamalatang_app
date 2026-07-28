import 'package:flutter/material.dart';
import '../models/order.dart';
import '../theme.dart';

/// One order on the board, laid out as a prep instruction rather than a receipt —
/// the same ordering as the web console's make ticket, so staff moving between
/// the two are not relearning where to look.
class OrderCardView extends StatelessWidget {
  const OrderCardView({super.key, required this.order});
  final TerminalOrder order;

  static const _statusLabel = {
    'PENDING': 'NEU',
    'CONFIRMED': 'ANGENOMMEN',
    'PREPARING': 'IN ARBEIT',
    'READY': 'FERTIG',
  };

  static const _statusColor = {
    'PENDING': PandaColors.amber,
    'CONFIRMED': Color(0xFF2563EB),
    'PREPARING': Color(0xFFEA580C),
    'READY': PandaColors.sichuan,
  };

  static const _spice = {
    'NONE': 'OHNE',
    'LIGHT': 'MILD',
    'MEDIUM': 'MITTEL',
    'HOT': 'SEHR SCHARF',
  };

  String get _pickup {
    final p = order.pickupTime;
    if (p == null) return 'sofort';
    return '${p.hour.toString().padLeft(2, '0')}:'
        '${p.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PandaColors.paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PandaColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '#${order.id.toString().padLeft(4, '0')}',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (_statusColor[order.status] ?? PandaColors.inkSoft)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _statusLabel[order.status] ?? order.status,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _statusColor[order.status] ?? PandaColors.inkSoft,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                _pickup,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),

          if (order.customerName != null || order.customerPhone != null) ...[
            const SizedBox(height: 4),
            Text(
              [order.customerName, order.customerPhone]
                  .whereType<String>()
                  .join(' · '),
              style: const TextStyle(fontSize: 13, color: PandaColors.inkSoft),
            ),
          ],

          // Drinks first and largest: this app exists for the tea counter.
          if (order.drinks.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final d in order.drinks) _DrinkLine(drink: d),
          ],

          for (final b in order.bowls) _BowlBlock(bowl: b),

          if (order.notes != null && order.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '„${order.notes!.trim()}“',
              style: const TextStyle(
                fontStyle: FontStyle.italic,
                color: PandaColors.inkSoft,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DrinkLine extends StatelessWidget {
  const _DrinkLine({required this.drink});
  final OrderDrink drink;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quantity in its own fixed column so a column of lines can be counted
          // down at a glance without reading the names.
          SizedBox(
            width: 42,
            child: Text(
              '${drink.quantity}×',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  drink.name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                if (drink.options.isNotEmpty)
                  Text(
                    '+ ${drink.options.join(" · ")}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: PandaColors.chilliDeep,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BowlBlock extends StatelessWidget {
  const _BowlBlock({required this.bowl});
  final OrderBowl bowl;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: PandaColors.cream,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${bowl.amount.toStringAsFixed(2)} € → ca. ${bowl.targetWeightG} g',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          // Broth largest — it is the one thing that cannot be fixed after the
          // bowl is made.
          Row(
            children: [
              const _Label('BRÜHE'),
              Expanded(
                child: Text(
                  bowl.soupBase,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              if (bowl.spiceLevel != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: PandaColors.chilli,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    OrderCardView._spice[bowl.spiceLevel] ?? bowl.spiceLevel!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          if (bowl.boil.isNotEmpty)
            Row(children: [const _Label('KOCHEN'), Expanded(child: Text(bowl.boil.join(' · ')))]),
          if (bowl.toppings.isNotEmpty)
            Row(children: [
              const _Label('TOPPING'),
              Expanded(child: Text(bowl.toppings.join(' · '))),
            ]),
          // Red, bold, never abbreviated. This is where allergies live.
          if (bowl.exclude.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: PandaColors.chilli.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: PandaColors.chilliDeep, size: 20),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'OHNE: ${bowl.exclude.join(", ")}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: PandaColors.chilliDeep,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (bowl.note != null && bowl.note!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('„${bowl.note!.trim()}“',
                  style: const TextStyle(fontStyle: FontStyle.italic)),
            ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 82,
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: PandaColors.inkSoft,
            letterSpacing: 0.5,
          ),
        ),
      );
}
