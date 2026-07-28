import 'dart:async';
import 'package:flutter/foundation.dart';
import '../api/terminal_api.dart';
import '../models/order.dart';

/// Polls the order feed and decides what counts as new.
///
/// "New" is deliberately the app's judgement, not the server's: the feed returns
/// everything open, and this compares it against the ids already seen. A terminal
/// that was asleep, offline or restarting therefore catches up on its next poll
/// instead of having silently missed the alert.
class OrderPoller extends ChangeNotifier {
  OrderPoller({required TerminalApi api, this.interval = const Duration(seconds: 10)})
      : _api = api;

  // Not `final`: re-pairing swaps the client without rebuilding the poller, which
  // would lose the set of ids already seen and re-alarm on everything.
  TerminalApi _api;
  // ignore_for_file: prefer_initializing_formals
  final Duration interval;

  Timer? _timer;
  final Set<int> _seen = <int>{};

  List<TerminalOrder> orders = const [];
  String terminalName = '';

  /// Orders that arrived since the last acknowledgement — what the alarm is about.
  List<TerminalOrder> pending = const [];

  DateTime? lastSuccess;
  int consecutiveFailures = 0;
  bool unauthorized = false;

  /// Two misses is ~20 seconds of silence. Worth saying out loud, because a
  /// terminal that has quietly stopped receiving looks exactly like a quiet shop.
  bool get isOffline => consecutiveFailures >= 2;

  /// Human-readable connection state, shown permanently rather than only on
  /// failure: silence from a terminal looks identical to a quiet shop, so the
  /// screen has to say which it is.
  String get lastSeenSummary {
    if (lastSuccess == null) return 'noch keine Verbindung';
    final secs = DateTime.now().difference(lastSuccess!).inSeconds;
    if (secs < 20) return 'aktualisiert gerade eben';
    if (secs < 120) return 'aktualisiert vor $secs s';
    return 'aktualisiert vor ${(secs / 60).floor()} Min.';
  }

  void start() {
    _timer?.cancel();
    // Immediately, then on the interval: a staff member who just opened the app
    // should not wait ten seconds to find out there are four orders waiting.
    unawaited(poll());
    _timer = Timer.periodic(interval, (_) => poll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void updateApi(TerminalApi api) {
    _api = api;
  }

  Future<void> poll() async {
    try {
      final feed = await _api.fetchOrders();
      terminalName = feed.terminalName;
      orders = feed.orders;
      lastSuccess = DateTime.now();
      consecutiveFailures = 0;
      unauthorized = false;

      // First poll after launch seeds `_seen` without alarming: everything open
      // at startup has presumably already been dealt with by a human, and an
      // alarm for eight old orders on every app restart would train staff to
      // ignore it.
      final firstPoll = _seen.isEmpty && _bootstrapping;
      for (final o in feed.orders) {
        if (!_seen.contains(o.id) && o.isNew && !firstPoll) {
          _pending.add(o.id);
        }
        _seen.add(o.id);
      }
      _bootstrapping = false;

      // Anything acknowledged elsewhere (the web console, another terminal) stops
      // being pending here too, so the alarm does not outlive the reason for it.
      _pending.removeWhere((id) {
        final match = feed.orders.where((o) => o.id == id);
        return match.isEmpty || !match.first.isNew;
      });
      pending = feed.orders.where((o) => _pending.contains(o.id)).toList();
    } on TerminalUnauthorized {
      // Revoked or re-paired elsewhere. Distinct from a network failure: this one
      // needs a human with a pairing code, and retrying forever would never fix it.
      unauthorized = true;
      stop();
    } catch (_) {
      consecutiveFailures++;
    }
    notifyListeners();
  }

  bool _bootstrapping = true;
  final Set<int> _pending = <int>{};

  /// Called when a human presses the accept button.
  Future<void> acknowledge(int orderId) async {
    _pending.remove(orderId);
    pending = orders.where((o) => _pending.contains(o.id)).toList();
    notifyListeners();
    try {
      await _api.acknowledge(orderId);
    } catch (_) {
      // The alarm is already silenced locally and that is the right priority: the
      // staff member has seen the order. The next poll reconciles the status, and
      // the order is still on the board either way.
    }
    await poll();
  }

  Future<void> acknowledgeAll() async {
    for (final id in List<int>.from(_pending)) {
      await acknowledge(id);
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
