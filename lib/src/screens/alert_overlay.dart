import 'dart:async';
import 'package:flutter/material.dart';
import '../models/order.dart';
import '../theme.dart';

/// The alarm screen.
///
/// Full-bleed, loud, and with exactly one way out. Everything here is chosen to
/// be hard to dismiss reflexively — an alert that can be swiped away gets swiped
/// away without being read, and the order is missed anyway.
class AlertOverlay extends StatefulWidget {
  const AlertOverlay({
    super.key,
    required this.orders,
    required this.onAcknowledgeAll,
    required this.onEscalate,
  });

  final List<TerminalOrder> orders;
  final Future<void> Function() onAcknowledgeAll;

  /// Called once, after a minute unacknowledged. A shop mid-rush is loud and the
  /// first pass can genuinely go unheard.
  final VoidCallback onEscalate;

  @override
  State<AlertOverlay> createState() => _AlertOverlayState();
}

class _AlertOverlayState extends State<AlertOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  Timer? _escalation;
  bool _escalated = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);

    _escalation = Timer(const Duration(seconds: 60), () {
      if (!mounted) return;
      setState(() => _escalated = true);
      widget.onEscalate();
    });
  }

  @override
  void dispose() {
    _escalation?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.orders.length;

    // Back button does nothing. Deliberate: on Android this is the reflex that
    // would otherwise dismiss the alarm without anyone reading the order.
    return PopScope(
      canPop: false,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final t = _pulse.value;
          final bg = _escalated
              // Once escalated the whole screen breathes between the two reds, so
              // it catches peripheral vision from across the shop.
              ? Color.lerp(PandaColors.chilli, PandaColors.chilliDeep, t)!
              : PandaColors.chilli;

          return Material(
            color: bg,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.notifications_active,
                            color: Colors.white, size: 34),
                        const SizedBox(width: 10),
                        Text(
                          count == 1 ? 'NEUE BESTELLUNG' : '$count NEUE BESTELLUNGEN',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView.separated(
                        itemCount: count,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (_, i) => _AlertCard(order: widget.orders[i]),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // The only exit. Full width, tall, unmissable.
                    SizedBox(
                      width: double.infinity,
                      height: 76,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: PandaColors.chilliDeep,
                          textStyle: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        onPressed: _busy
                            ? null
                            : () async {
                                setState(() => _busy = true);
                                await widget.onAcknowledgeAll();
                              },
                        child: Text(_busy
                            ? 'Wird übernommen …'
                            : count == 1
                                ? 'ANNEHMEN'
                                : 'ALLE ANNEHMEN'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A single order, summarised for the two seconds someone looks at it before
/// pressing accept. Drinks first, because that is what this app is for.
class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.order});
  final TerminalOrder order;

  @override
  Widget build(BuildContext context) {
    final pickup = order.pickupTime;
    final time = pickup == null
        ? 'sofort'
        : '${pickup.hour.toString().padLeft(2, '0')}:'
            '${pickup.minute.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '#${order.id.toString().padLeft(4, '0')}',
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              Text(
                time,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: PandaColors.inkSoft,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final d in order.drinks)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${d.quantity}× ${d.name}'
                '${d.options.isEmpty ? '' : ' + ${d.options.join(", ")}'}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
          for (final b in order.bowls)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '🍲 ${b.amount.toStringAsFixed(2)} € · ${b.soupBase}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
          // Exclusions surface even on the alert card. This is the one thing that
          // must not wait until someone opens the detail view.
          for (final b in order.bowls)
            if (b.exclude.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: PandaColors.chilli.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '⚠ OHNE: ${b.exclude.join(", ")}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: PandaColors.chilliDeep,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
