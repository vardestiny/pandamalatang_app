import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/alarm.dart';
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
    required this.onUnpair,
  });

  final OrderPoller poller;
  final Alarm alarm;
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

  @override
  Widget build(BuildContext context) {
    final poller = widget.poller;

    if (poller.unauthorized) return _unauthorized();

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

    final open = poller.orders
        .where((o) => o.status != 'COMPLETED' && o.status != 'CANCELLED')
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          poller.terminalName.isEmpty ? 'Terminal' : poller.terminalName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Profil',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ProfileScreen(
                  poller: poller,
                  alarm: widget.alarm,
                  onUnpair: widget.onUnpair,
                ),
              ),
            ),
          ),
        ],
        bottom: poller.isOffline ? const _OfflineBanner() : null,
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
                        const Text(
                          'Keine offenen Bestellungen',
                          style: TextStyle(fontSize: 18, color: PandaColors.inkSoft),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _lastSeenText(poller),
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
                          _lastSeenText(poller),
                          style: const TextStyle(
                            fontSize: 12,
                            color: PandaColors.inkSoft,
                          ),
                        ),
                      ),
                    );
                  }
                  return OrderCardView(order: open[i]);
                },
              ),
      ),
    );
  }

  Widget _unauthorized() => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.link_off, size: 48, color: PandaColors.chilli),
                const SizedBox(height: 12),
                const Text(
                  'Dieses Terminal wurde gesperrt',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Im Admin einen neuen Kopplungscode erzeugen und das Gerät '
                  'erneut koppeln.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: PandaColors.inkSoft),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: widget.onUnpair,
                  child: const Text('Neu koppeln'),
                ),
              ],
            ),
          ),
        ),
      );
}

String _lastSeenText(OrderPoller poller) {
  final t = poller.lastSeenSummary;
  return t;
}

class _OfflineBanner extends StatelessWidget implements PreferredSizeWidget {
  const _OfflineBanner();

  @override
  Size get preferredSize => const Size.fromHeight(34);

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: PandaColors.chilli,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: const Text(
          'KEINE VERBINDUNG — Bestellungen kommen gerade nicht an',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 13,
          ),
        ),
      );
}
