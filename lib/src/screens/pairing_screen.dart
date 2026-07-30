import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/app_localizations.dart';
import '../api/terminal_api.dart';
import '../services/credentials.dart';
import '../theme.dart';
import '../widgets/panda_logo.dart';

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
  bool _showAdvanced = false;

  /// What went wrong, as a reason. Turned into a sentence at build time so it is
  /// still in the right language if someone changes the language while looking
  /// at it.
  _PairError? _error;

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
      setState(() => _error = _PairError.shortCode);
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
      if (mounted) {
        setState(() => _error = switch (e.reason) {
              PairingFailure.rateLimited => _PairError.rateLimited,
              PairingFailure.invalidCode => _PairError.invalidCode,
            });
      }
    } catch (_) {
      if (mounted) setState(() => _error = _PairError.unreachable);
    } finally {
      api.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const PandaLogo(height: 76),
                const SizedBox(height: 12),
                Text(
                  l.pairTitle,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  l.pairIntro,
                  style: const TextStyle(color: PandaColors.inkSoft),
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
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: l.pairCodeHint,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!.text(l),
                    style: const TextStyle(color: PandaColors.chilli),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy ? l.pairSubmitBusy : l.pairSubmit),
                ),
                const SizedBox(height: 12),
                // Hidden by default: the URL is right in every normal case, and a
                // visible server field invites someone to "fix" a working one.
                TextButton(
                  onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
                  child: Text(_showAdvanced ? l.pairAdvancedHide : l.pairAdvanced),
                ),
                if (_showAdvanced)
                  TextField(
                    controller: _baseUrl,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: l.fieldServer,
                      border: const OutlineInputBorder(),
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

/// Why pairing did not work. Held as a reason rather than a sentence so the
/// screen can render it in whatever language is current when it is shown.
enum _PairError {
  shortCode,
  unreachable,
  rateLimited,
  invalidCode;

  String text(L l) => switch (this) {
        _PairError.shortCode => l.pairErrorShortCode,
        _PairError.unreachable => l.pairErrorUnreachable,
        _PairError.rateLimited => l.pairErrorRateLimited,
        _PairError.invalidCode => l.pairErrorInvalidCode,
      };
}
