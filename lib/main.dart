import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io' show Platform;

import 'src/api/terminal_api.dart';
import 'src/screens/board_screen.dart';
import 'src/screens/pairing_screen.dart';
import 'src/services/alarm.dart';
import 'src/services/credentials.dart';
import 'src/services/order_poller.dart';
import 'src/theme.dart';

void main() {
  runApp(const TerminalApp());
}

class TerminalApp extends StatelessWidget {
  const TerminalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Panda Malatang Terminal',
      debugShowCheckedModeBanner: false,
      theme: pandaTheme(),
      home: const _Root(),
    );
  }
}

/// Decides between pairing and the board, and owns the objects that must outlive
/// a screen: the poller (which holds the set of already-seen order ids) and the
/// alarm (which holds the audio player).
class _Root extends StatefulWidget {
  const _Root();

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

    return BoardScreen(poller: poller, alarm: _alarm, onUnpair: _unpair);
  }
}
