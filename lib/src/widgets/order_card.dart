import 'dart:async';

import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../l10n_ext.dart';
import '../models/order.dart';
import '../theme.dart';

/// One order on the board, laid out as a prep instruction rather than a receipt —
/// the same ordering as the web console's make ticket, so staff moving between
/// the two are not relearning where to look.
class OrderCardView extends StatefulWidget {
  const OrderCardView({super.key, required this.order, this.onAdvance});
  final TerminalOrder order;

  /// Takes the order one step along the path. Null makes the card read-only,
  /// which is what the alert overlay wants — the only button there is Annehmen.
  final Future<void> Function(String next)? onAdvance;

  static const _statusColor = {
    'PENDING': PandaColors.amber,
    'CONFIRMED': Color(0xFF2563EB),
    'PREPARING': Color(0xFFEA580C),
    'READY': PandaColors.sichuan,
    'COMPLETED': PandaColors.inkSoft,
  };

  /// The button's words come from the ARB files, and are the web console's own
  /// (`nextCONFIRMED` … `nextCOMPLETED`): one member of staff uses both screens,
  /// sometimes within a minute.
  static const _nextIcon = {
    'CONFIRMED': Icons.check,
    'PREPARING': Icons.soup_kitchen,
    'READY': Icons.done_all,
    'COMPLETED': Icons.shopping_bag,
  };

  @override
  State<OrderCardView> createState() => _OrderCardViewState();
}

class _OrderCardViewState extends State<OrderCardView> {
  /// True from the tap until shortly after the server answers.
  ///
  /// The lock outlasts the request on purpose. The button relabels itself the
  /// moment a step lands — that is the feedback — so an impatient second tap
  /// would land on the *next* step, in the same place, a few hundred
  /// milliseconds later. Two taps on "Fertig" would hand over an order that is
  /// still on the counter.
  bool _busy = false;
  Timer? _settle;

  @override
  void dispose() {
    _settle?.cancel();
    super.dispose();
  }

  Future<void> _step(String next) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onAdvance!(next);
    } finally {
      _settle?.cancel();
      _settle = Timer(const Duration(milliseconds: 700), () {
        if (mounted) setState(() => _busy = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final l = L.of(context);
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
                l.orderNumber(order.reference),
                // Tracked out: the code is letters as well as digits now, and
                // a staff member reads it back against what a customer says.
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (OrderCardView._statusColor[order.status] ??
                          PandaColors.inkSoft)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  l.statusBadge(order.status),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: OrderCardView._statusColor[order.status] ??
                        PandaColors.inkSoft,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                l.pickupAt(order.pickupTime),
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
              l.quoted(order.notes!.trim()),
              style: const TextStyle(
                fontStyle: FontStyle.italic,
                color: PandaColors.inkSoft,
              ),
            ),
          ],

          if (widget.onAdvance != null && order.nextStatus != null)
            _StepButton(
              next: order.nextStatus!,
              busy: _busy,
              onPressed: () => _step(order.nextStatus!),
            ),
        ],
      ),
    );
  }
}

/// The one button on the card, and the whole reason an order moves.
///
/// Full width and 56 high because it is pressed with a thumb, at speed, by
/// someone holding a cup in the other hand — and because a miss that lands on
/// the card instead does nothing, which is the correct outcome of a mistake.
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.next,
    required this.busy,
    required this.onPressed,
  });

  final String next;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // Handover is the step that takes the order off the board, so it is the one
    // that looks different. Every other step is reversible by simply carrying on.
    final isHandover = next == 'COMPLETED';

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: FilledButton.icon(
          onPressed: busy ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: isHandover ? PandaColors.sichuan : PandaColors.ink,
            foregroundColor: Colors.white,
            disabledBackgroundColor: PandaColors.inkSoft.withValues(alpha: 0.35),
            disabledForegroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Icon(OrderCardView._nextIcon[next] ?? Icons.arrow_forward,
                  size: 24),
          label: Text(
            L.of(context).stepLabel(next),
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
          ),
        ),
      ),
    );
  }
}

class _DrinkLine extends StatelessWidget {
  const _DrinkLine({required this.drink});
  final OrderDrink drink;

  @override
  Widget build(BuildContext context) {
    final prep = L.of(context).preparation(drink);
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
                // Above the paid add-ons: this is the drink itself, and getting
                // it wrong means pouring the cup again.
                if (prep != null)
                  Text(
                    prep,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: PandaColors.ink,
                    ),
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
    final l = L.of(context);
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
            l.bowlTarget(l.money(bowl.amount), bowl.targetWeightG),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          // Broth largest — it is the one thing that cannot be fixed after the
          // bowl is made.
          Row(
            children: [
              _Label(l.labelBroth),
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
                    l.spice(bowl.spiceLevel!),
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
            Row(children: [_Label(l.labelBoil), Expanded(child: Text(bowl.boil.join(' · ')))]),
          if (bowl.toppings.isNotEmpty)
            Row(children: [
              _Label(l.labelTopping),
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
                      l.without(bowl.exclude.join(', ')),
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
              child: Text(l.quoted(bowl.note!.trim()),
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
