import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../l10n_ext.dart';
import '../services/alarm.dart';
import '../services/app_settings.dart';
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
    required this.settings,
    required this.onUnpair,
  });

  final OrderPoller poller;
  final Alarm alarm;
  final AppSettings settings;
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
    final l = L.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.profileTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Row(l.fieldName, p.terminalName.isEmpty ? '—' : p.terminalName),
          _Row(l.fieldServer, _baseUrl ?? '—'),
          _Row(l.fieldPaired, _pairedAt == null ? '—' : l.date(_pairedAt!)),
          _Row(l.fieldConnection, l.lastSeen(p)),
          _Row(l.fieldOpenOrders, '${p.orders.length}'),

          const SizedBox(height: 8),
          _LanguagePicker(settings: widget.settings),

          const SizedBox(height: 24),

          FilledButton.icon(
            onPressed: () async {
              await widget.alarm.test();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l.testSoundPlayed)),
              );
            },
            icon: const Icon(Icons.volume_up),
            label: Text(l.testSound),
          ),
          const SizedBox(height: 10),
          Text(
            l.testSoundHint,
            style: const TextStyle(fontSize: 13, color: PandaColors.inkSoft),
          ),

          const SizedBox(height: 32),
          OutlinedButton.icon(
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(l.unpairTitle),
                  content: Text(l.unpairBody),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(l.cancel),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(l.unpair),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;
              await _credentials.clear();
              widget.onUnpair();
            },
            icon: const Icon(Icons.link_off),
            label: Text(l.unpair),
            style: OutlinedButton.styleFrom(foregroundColor: PandaColors.chilli),
          ),
        ],
      ),
    );
  }
}

/// Language, as segmented buttons rather than a dropdown.
///
/// Four flat choices, all visible: someone who has landed in a language they
/// cannot read needs to recognise their own without first working out how to
/// open a menu. Each language is written in itself for the same reason.
class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        // Not just for the labels: switching from "device language" to the
        // language the device already uses changes nothing about the text, and
        // the chip would stay on the wrong choice without this.
        listenable: settings,
        builder: (context, _) => _build(context),
      );

  Widget _build(BuildContext context) {
    final l = L.of(context);
    final current = settings.locale?.languageCode;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              l.fieldLanguage,
              style: const TextStyle(color: PandaColors.inkSoft, fontSize: 14),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (code, label) in [
                  (null, l.languageSystem),
                  ('de', l.languageGerman),
                  ('en', l.languageEnglish),
                  ('zh', l.languageChinese),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: current == code,
                    onSelected: (_) => settings.setLocale(
                      code == null ? null : Locale(code),
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
