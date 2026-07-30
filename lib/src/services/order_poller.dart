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

  /// Seconds since the last successful poll, or null if there has not been one.
  ///
  /// The sentence this turns into lives in `lastSeenText` on the widget side:
  /// this class has no `BuildContext` and therefore no language.
  int? get secondsSinceLastSuccess => lastSuccess == null
      ? null
      : DateTime.now().difference(lastSuccess!).inSeconds;

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

  /// Tell the server which language to name the food in.
  ///
  /// Polls straight away when it changes, rather than leaving the board in the
  /// old language for up to ten seconds: somebody who just switched language is
  /// looking at the screen, and a board that does not react reads as a setting
  /// that did not take.
  void setLocale(String code) {
    if (_api.localeCode == code) return;
    _api.localeCode = code;
    unawaited(poll());
  }

  Future<void> poll() async {
    try {
      final feed = await _api.fetchOrders();
      terminalName = feed.terminalName;
      _feed = feed.orders;
      _rebuild();
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

  /// The feed exactly as the server sent it, before local intent is laid over it.
  /// Kept separate so a step that fails can be taken back off again.
  List<TerminalOrder> _feed = const [];

  /// Steps a human has tapped that the server has not confirmed back yet.
  ///
  /// The poll runs every ten seconds. Without this, a card would sit unchanged
  /// for most of that after a tap, and the second tap that provokes is a step
  /// skipped rather than a step repeated.
  final Map<int, String> _localStatus = <int, String>{};

  /// Rebuild the visible board from the feed plus whatever is still in flight.
  void _rebuild() {
    if (_localStatus.isEmpty) {
      orders = _feed;
      return;
    }
    // An order that has left the feed is finished or cancelled; either way the
    // server has spoken and there is nothing left to hold on its behalf.
    final present = _feed.map((o) => o.id).toSet();
    _localStatus.removeWhere((id, _) => !present.contains(id));

    orders = [
      for (final o in _feed) _localStatus[o.id] == null ? o : _merge(o),
    ];
  }

  TerminalOrder _merge(TerminalOrder o) {
    final wanted = _localStatus[o.id]!;
    final here = orderFlowIndex(o.status);
    // Caught up — or somewhere off the path entirely, which only a cancellation
    // does, and a cancellation outranks anything this tablet wanted.
    if (here < 0 || here >= orderFlowIndex(wanted)) {
      _localStatus.remove(o.id);
      return o;
    }
    return o.withStatus(wanted);
  }

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

  /// Called when a human presses the step button on a card — Kochen, Fertig,
  /// Abgeholt, or the undo that puts a handover back.
  ///
  /// Returns the status the order ended up in, or null if the step did not
  /// happen at all. A null is worth showing: unlike the alarm, where silencing
  /// locally is the right answer even offline, a step nobody recorded means the
  /// other screen and the next shift do not know about it.
  Future<String?> advance(int orderId, String status) async {
    // Stepping past a still-ringing order is an acknowledgement as well; the
    // alarm must not outlive the tap that dealt with the order.
    if (_pending.remove(orderId)) {
      pending = orders.where((o) => _pending.contains(o.id)).toList();
    }

    _localStatus[orderId] = status;
    _rebuild();
    notifyListeners();

    String? settled;
    try {
      settled = await _api.setStatus(orderId, status);
      // The server is allowed to disagree — forward-only, and this board may be
      // a poll behind. Show where the order really is.
      _localStatus[orderId] = settled;
    } on TerminalUnauthorized {
      unauthorized = true;
      stop();
      notifyListeners();
      return null;
    } catch (_) {
      _localStatus.remove(orderId);
      _rebuild();
      notifyListeners();
      return null;
    }

    await poll();
    return settled;
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
