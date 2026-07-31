import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../l10n_ext.dart';
import '../models/order.dart';
import '../services/order_poller.dart';
import '../theme.dart';
import '../widgets/order_card.dart';

/// Today's orders, newest first.
///
/// The board is a work queue: an order leaves it the moment it is handed over,
/// which is right during a rush and useless ten minutes later when the customer
/// comes back holding a code and a question. This is the record.
///
/// **Today only, deliberately.** Yesterday's takings are a reporting question and
/// belong in the admin console on a screen with a keyboard — not on a counter
/// tablet, where a growing list would need pagination, a date picker and a reason
/// to trust the numbers. Bounded to one day, it is a single tap and one request.
///
/// Fetched once when opened, and again on pull-to-refresh. Not added to the
/// ten-second poll: this is a screen someone looks at, not an alarm, and polling it
/// would triple the query load for a list nobody has open.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.poller});

  final OrderPoller poller;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  OrderHistory? _history;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _failed = false);
    try {
      final history = await widget.poller.fetchHistory();
      if (mounted) {
        setState(() {
          _history = history;
          _loading = false;
        });
      }
    } catch (_) {
      // The reason does not change what a staff member can do about it, and the
      // board behind this screen is still live either way. Say it failed and offer
      // the retry.
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final history = _history;

    return Scaffold(
      appBar: AppBar(title: Text(l.historyTitle)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: switch (_loading) {
          true => const Center(child: CircularProgressIndicator()),
          false when _failed => _Message(
              text: l.historyFailed,
              action: TextButton(onPressed: _load, child: Text(l.historyRetry)),
            ),
          false when history == null || history.orders.isEmpty =>
            _Message(text: l.historyEmpty),
          false => ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _DaySummary(history: history!),
                if (history.truncated)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      l.historyTruncated,
                      style: const TextStyle(
                        fontSize: 13,
                        color: PandaColors.inkSoft,
                      ),
                    ),
                  ),
                // The same card as the board, with no step callback — which is
                // what makes it read-only. A finished order must not offer a
                // button that would walk it somewhere.
                for (final order in history.orders) OrderCardView(order: order),
              ],
            ),
        },
      ),
    );
  }
}

/// Count and takings for the day, at the top where it is read at closing time.
class _DaySummary extends StatelessWidget {
  const _DaySummary({required this.history});

  final OrderHistory history;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PandaColors.creamDeep,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.historySummary(history.count),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              // Only when there are any. A permanent "0 cancelled" is noise, and
              // this line exists to explain why the total is lower than the list
              // looks.
              if (history.cancelled > 0)
                Text(
                  l.historyCancelled(history.cancelled),
                  style: const TextStyle(fontSize: 13, color: PandaColors.inkSoft),
                ),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                l.historyTakings,
                style: const TextStyle(fontSize: 12, color: PandaColors.inkSoft),
              ),
              Text(
                l.money(history.total),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Empty and failed states. A `ListView` rather than a bare `Center` so
/// pull-to-refresh still works when there is nothing to pull.
class _Message extends StatelessWidget {
  const _Message({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => ListView(
        children: [
          const SizedBox(height: 120),
          Center(
            child: Column(
              children: [
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17, color: PandaColors.inkSoft),
                ),
                if (action != null) ...[const SizedBox(height: 8), action!],
              ],
            ),
          ),
        ],
      );
}
