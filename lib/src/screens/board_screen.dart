import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../l10n/app_localizations.dart';
import '../l10n_ext.dart';
import '../services/alarm.dart';
import '../services/app_settings.dart';
import '../services/order_poller.dart';
import '../theme.dart';
import '../widgets/order_card.dart';
import 'alert_overlay.dart';
import 'profile_screen.dart';

/// The screen the tablet sits on all day.
class BoardScreen extends StatefulWidget {
  const BoardScreen({
    super.key,
    required this.poller,
    required this.alarm,
    required this.settings,
    required this.onUnpair,
  });

  final OrderPoller poller;
  final Alarm alarm;
  final AppSettings settings;
  final VoidCallback onUnpair;

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  @override
  void initState() {
    super.initState();
    // A tablet that has gone to sleep cannot show an alarm. This is the whole
    // reason the app is worth installing rather than leaving the web console open.
    WakelockPlus.enable();
    widget.poller.addListener(_onPoll);
    widget.poller.start();
  }

  @override
  void dispose() {
    widget.poller.removeListener(_onPoll);
    WakelockPlus.disable();
    super.dispose();
  }

  void _onPoll() {
    final hasPending = widget.poller.pending.isNotEmpty;
    if (hasPending && !widget.alarm.isPlaying) {
      widget.alarm.start();
    } else if (!hasPending && widget.alarm.isPlaying) {
      widget.alarm.stop();
    }
    if (mounted) setState(() {});
  }

  /// Take an order one step, and say what happened.
  ///
  /// Every outcome is spoken out loud. A step that silently failed would leave
  /// the board looking finished while the console, the kitchen and the next
  /// shift still show the order sitting where it was.
  Future<void> _advance(int id, String next) async {
    final settled = await widget.poller.advance(id, next);
    if (!mounted) return;

    final l = L.of(context);
    final number = l.orderNumber(id);
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();

    if (settled == null) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: PandaColors.chilliDeep,
          duration: const Duration(seconds: 6),
          content: Text(l.stepFailed(number)),
        ),
      );
      return;
    }

    // Handover is the only step that takes the order off the board, so it is the
    // only one a staff member cannot correct by looking at the card. The undo is
    // therefore not a nicety: without it, one mistap means walking to the
    // console mid-rush.
    if (settled == 'COMPLETED') {
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(l.handedOver(number)),
          action: SnackBarAction(
            label: l.undo,
            onPressed: () => widget.poller.advance(id, 'READY'),
          ),
        ),
      );
      return;
    }

    // The board is a poll behind now and then; if the server had already moved
    // the order on, the card is about to change to something the tap did not
    // ask for and that needs saying rather than just happening.
    if (settled != next) {
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Text(l.alreadyAt(number, l.statusName(settled))),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final poller = widget.poller;
    final l = L.of(context);

    if (poller.unauthorized) return _unauthorized(l);

    // The alarm takes the entire screen. Not a dialog over the board: a dialog
    // has a barrier that can be tapped, and this one must not.
    if (poller.pending.isNotEmpty) {
      return AlertOverlay(
        orders: poller.pending,
        onAcknowledgeAll: () async {
          await poller.acknowledgeAll();
          await widget.alarm.stop();
        },
        onEscalate: widget.alarm.escalate,
      );
    }

    final open = poller.orders.where((o) => o.isOpen).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          poller.terminalName.isEmpty ? l.boardTitleFallback : poller.terminalName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: l.profileTooltip,
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ProfileScreen(
                  poller: poller,
                  alarm: widget.alarm,
                  settings: widget.settings,
                  onUnpair: widget.onUnpair,
                ),
              ),
            ),
          ),
        ],
        bottom: poller.isOffline ? _OfflineBanner(l.offlineBanner) : null,
      ),
      body: RefreshIndicator(
        onRefresh: poller.poll,
        child: open.isEmpty
            ? ListView(
                children: [
                  const SizedBox(height: 120),
                  Center(
                    child: Column(
                      children: [
                        const Text('🧋', style: TextStyle(fontSize: 56)),
                        const SizedBox(height: 12),
                        Text(
                          l.boardEmpty,
                          style: const TextStyle(
                              fontSize: 18, color: PandaColors.inkSoft),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l.lastSeen(poller),
                          style: const TextStyle(
                            fontSize: 13,
                            color: PandaColors.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: open.length + 1,
                itemBuilder: (_, i) {
                  if (i == open.length) {
                    // Footer, not a header: connection state is reassurance, not
                    // the thing being looked for, and it belongs out of the way
                    // until it turns into the offline banner.
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          l.lastSeen(poller),
                          style: const TextStyle(
                            fontSize: 12,
                            color: PandaColors.inkSoft,
                          ),
                        ),
                      ),
                    );
                  }
                  final order = open[i];
                  return OrderCardView(
                    order: order,
                    onAdvance: (next) => _advance(order.id, next),
                  );
                },
              ),
      ),
    );
  }

  Widget _unauthorized(L l) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.link_off, size: 48, color: PandaColors.chilli),
                const SizedBox(height: 12),
                Text(
                  l.lockedTitle,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  l.lockedBody,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: PandaColors.inkSoft),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: widget.onUnpair,
                  child: Text(l.lockedAction),
                ),
              ],
            ),
          ),
        ),
      );
}

class _OfflineBanner extends StatelessWidget implements PreferredSizeWidget {
  const _OfflineBanner(this.text);

  final String text;

  @override
  Size get preferredSize => const Size.fromHeight(34);

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: PandaColors.chilli,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 13,
          ),
        ),
      );
}
