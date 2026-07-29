import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io' show Platform;

import 'l10n/app_localizations.dart';
import 'src/api/terminal_api.dart';
import 'src/screens/board_screen.dart';
import 'src/screens/pairing_screen.dart';
import 'src/services/alarm.dart';
import 'src/services/app_settings.dart';
import 'src/services/credentials.dart';
import 'src/services/order_poller.dart';
import 'src/theme.dart';

void main() {
  runApp(const TerminalApp());
}

class TerminalApp extends StatefulWidget {
  const TerminalApp({super.key});

  @override
  State<TerminalApp> createState() => _TerminalAppState();
}

class _TerminalAppState extends State<TerminalApp> {
  final _settings = AppSettings();

  @override
  void initState() {
    super.initState();
    // Before the first frame the stored language is not known yet, so the app
    // opens in the device's. That flicker lasts one frame and only on a tablet
    // whose language differs from its setting — the alternative is a splash
    // screen on every launch to avoid it.
    _settings.load();
  }

  @override
  void dispose() {
    _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) => MaterialApp(
        onGenerateTitle: (context) => L.of(context).appTitle,
        debugShowCheckedModeBanner: false,
        theme: pandaTheme(),
        // Null means the device decides. An unsupported device language falls
        // back to the first entry, German — the shop's own.
        locale: _settings.locale,
        localizationsDelegates: L.localizationsDelegates,
        supportedLocales: L.supportedLocales,
        home: _Root(settings: _settings),
      ),
    );
  }
}

/// Decides between pairing and the board, and owns the objects that must outlive
/// a screen: the poller (which holds the set of already-seen order ids) and the
/// alarm (which holds the audio player).
class _Root extends StatefulWidget {
  const _Root({required this.settings});

  final AppSettings settings;

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  final _credentials = Credentials();
  final _alarm = Alarm();

  OrderPoller? _poller;
  bool _loading = true;
  String _deviceLabel = 'Tablet';

  @override
  void initState() {
    super.initState();
    // Landscape-friendly but not forced: some shops wall-mount in portrait.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _boot();
  }

  @override
  void dispose() {
    _poller?.dispose();
    _alarm.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    _deviceLabel = await _describeDevice();
    final token = await _credentials.token();
    if (token != null) await _attach(token);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _attach(String token) async {
    final baseUrl = await _credentials.baseUrl();
    final api = TerminalApi(baseUrl: baseUrl, token: token);
    final poller = OrderPoller(api: api);
    if (mounted) setState(() => _poller = poller);
  }

  /// Reported at pairing so a lost tablet can be identified in the console. Best
  /// effort: a device that will not describe itself should still be able to pair.
  Future<String> _describeDevice() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        return '${a.manufacturer} ${a.model} (Android ${a.version.release})';
      }
      if (Platform.isIOS) {
        final i = await info.iosInfo;
        return '${i.name} (iOS ${i.systemVersion})';
      }
    } catch (_) {
      // Fall through.
    }
    return 'Tablet';
  }

  Future<void> _unpair() async {
    await _alarm.stop();
    _poller?.dispose();
    await _credentials.clear();
    if (mounted) setState(() => _poller = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final poller = _poller;
    if (poller == null) {
      return PairingScreen(
        deviceLabel: _deviceLabel,
        onPaired: () async {
          final token = await _credentials.token();
          if (token != null) await _attach(token);
        },
      );
    }

    return BoardScreen(
      poller: poller,
      alarm: _alarm,
      settings: widget.settings,
      onUnpair: _unpair,
    );
  }
}
