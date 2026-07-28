import 'package:flutter/material.dart';
import '../services/alarm.dart';
import '../services/credentials.dart';
import '../services/order_poller.dart';
import '../theme.dart';

/// Terminal identity and the one control that earns its place: test the sound.
///
/// The failure mode of an alarm app is a muted or turned-down device, and nothing
/// in the software can detect that. The only defence is having deliberately made a
/// noise before service rather than discovering it during.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.poller,
    required this.alarm,
    required this.onUnpair,
  });

  final OrderPoller poller;
  final Alarm alarm;
  final VoidCallback onUnpair;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _credentials = Credentials();
  String? _baseUrl;
  DateTime? _pairedAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final url = await _credentials.baseUrl();
    final paired = await _credentials.pairedAt();
    if (!mounted) return;
    setState(() {
      _baseUrl = url;
      _pairedAt = paired;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.poller;
    return Scaffold(
      appBar: AppBar(title: const Text('Terminal')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Row('Name', p.terminalName.isEmpty ? '—' : p.terminalName),
          _Row('Server', _baseUrl ?? '—'),
          _Row(
            'Gekoppelt',
            _pairedAt == null
                ? '—'
                : '${_pairedAt!.day}.${_pairedAt!.month}.${_pairedAt!.year}',
          ),
          _Row('Verbindung', p.lastSeenSummary),
          _Row('Offene Bestellungen', '${p.orders.length}'),
          const SizedBox(height: 24),

          FilledButton.icon(
            onPressed: () async {
              await widget.alarm.test();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Ton abgespielt. Nicht gehört? Lautstärke am Gerät prüfen.',
                  ),
                ),
              );
            },
            icon: const Icon(Icons.volume_up),
            label: const Text('Ton testen'),
          ),
          const SizedBox(height: 10),
          const Text(
            'Vor jedem Service einmal testen. Ein stummgeschaltetes Tablet ist der '
            'einzige Fehler, den die App selbst nicht erkennen kann.',
            style: TextStyle(fontSize: 13, color: PandaColors.inkSoft),
          ),

          const SizedBox(height: 32),
          OutlinedButton.icon(
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Terminal entkoppeln?'),
                  content: const Text(
                    'Das Gerät empfängt danach keine Bestellungen mehr. Für die '
                    'erneute Kopplung wird ein neuer Code aus dem Admin gebraucht.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Abbrechen'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Entkoppeln'),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;
              await _credentials.clear();
              widget.onUnpair();
            },
            icon: const Icon(Icons.link_off),
            label: const Text('Entkoppeln'),
            style: OutlinedButton.styleFrom(foregroundColor: PandaColors.chilli),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 160,
              child: Text(
                label,
                style: const TextStyle(color: PandaColors.inkSoft, fontSize: 14),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
}
