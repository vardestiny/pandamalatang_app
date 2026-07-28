import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api/terminal_api.dart';
import '../services/credentials.dart';
import '../theme.dart';

/// First launch: turn a pairing code from the admin console into a token.
class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key, required this.deviceLabel, required this.onPaired});

  final String deviceLabel;
  final VoidCallback onPaired;

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _code = TextEditingController();
  final _baseUrl = TextEditingController();
  final _credentials = Credentials();
  bool _busy = false;
  String? _error;
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    _credentials.baseUrl().then((v) {
      if (mounted) _baseUrl.text = v;
    });
  }

  @override
  void dispose() {
    _code.dispose();
    _baseUrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    if (code.length < 4) {
      setState(() => _error = 'Bitte den 6-stelligen Code eingeben.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final url = _baseUrl.text.trim().replaceAll(RegExp(r'/+$'), '');
    final api = TerminalApi(baseUrl: url);
    try {
      final result = await api.pair(code: code, deviceLabel: widget.deviceLabel);
      await _credentials.save(
        token: result.token,
        terminalName: result.terminalName,
        baseUrl: url,
      );
      if (mounted) widget.onPaired();
    } on PairingFailed catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Server nicht erreichbar. Verbindung prüfen.');
      }
    } finally {
      api.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('🐼', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 8),
                Text(
                  'Terminal koppeln',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Im Admin unter Terminals ein Gerät anlegen und den Code hier '
                  'eingeben.',
                  style: TextStyle(color: PandaColors.inkSoft),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _code,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  // Codes are read off a screen and typed by hand, so the field is
                  // oversized and monospaced-wide to make a typo obvious.
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 10,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                    TextInputFormatter.withFunction(
                      (_, next) => next.copyWith(text: next.text.toUpperCase()),
                    ),
                  ],
                  decoration: const InputDecoration(
                    counterText: '',
                    hintText: 'ABC123',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: PandaColors.chilli)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy ? 'Koppeln …' : 'Koppeln'),
                ),
                const SizedBox(height: 12),
                // Hidden by default: the URL is right in every normal case, and a
                // visible server field invites someone to "fix" a working one.
                TextButton(
                  onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
                  child: Text(_showAdvanced ? 'Erweitert ausblenden' : 'Erweitert'),
                ),
                if (_showAdvanced)
                  TextField(
                    controller: _baseUrl,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Server',
                      border: OutlineInputBorder(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
