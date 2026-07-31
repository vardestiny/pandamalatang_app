import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/order.dart';

/// Thrown when the server says the terminal is no longer who it claims to be.
/// Separate from a network failure on purpose: one means re-pair, the other means
/// wait. Treating them alike would either unpair a terminal over flaky wifi or
/// leave a revoked one retrying forever.
class TerminalUnauthorized implements Exception {
  const TerminalUnauthorized();
}

/// Why a pairing attempt did not work, as a reason rather than a sentence.
///
/// The app speaks three languages and this layer speaks none of them: a German
/// string thrown from here could not be translated by the screen that catches it.
enum PairingFailure {
  /// Unknown code, expired code, revoked terminal. Deliberately one case for all
  /// three — telling a guesser which of them they hit is free help.
  invalidCode,
  rateLimited,
}

class PairingFailed implements Exception {
  const PairingFailed(this.reason);
  final PairingFailure reason;
  @override
  String toString() => 'PairingFailed(${reason.name})';
}

class TerminalApi {
  TerminalApi({required this.baseUrl, this.token, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final String? token;
  final http.Client _client;

  /// The language this tablet is painted in, sent so the feed names the food in
  /// it. Not final: the picker in Profile changes it without re-pairing.
  ///
  /// Only the food needs the server's help. Statuses, spice and sugar are enum
  /// names the app translates itself — but "Koriander" exists nowhere in the
  /// app, and a cook who cannot read it is the whole point of the red line.
  String localeCode = 'de';

  // Long enough for a slow shop connection, short enough that a hung request
  // does not stall the next poll behind it.
  static const _timeout = Duration(seconds: 15);

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept-Language': localeCode,
        if (token != null) 'Authorization': 'Bearer $token',
      };

  /// Redeem a pairing code. Returns the token, once — the server stores only a
  /// hash and genuinely cannot repeat it.
  Future<({String token, String terminalName})> pair({
    required String code,
    required String deviceLabel,
  }) async {
    final res = await _client
        .post(
          _uri('/api/terminal/pair'),
          headers: _headers,
          body: jsonEncode({'code': code.trim().toUpperCase(), 'deviceLabel': deviceLabel}),
        )
        .timeout(_timeout);

    final body = _decode(res.body);
    if (res.statusCode == 429) {
      throw const PairingFailed(PairingFailure.rateLimited);
    }
    if (res.statusCode != 200 || body['token'] is! String) {
      throw const PairingFailed(PairingFailure.invalidCode);
    }
    return (
      token: body['token'] as String,
      terminalName: (body['terminal'] as Map<String, dynamic>?)?['name'] as String? ?? '',
    );
  }

  /// Everything currently open. See APP-PLAN §1 for why this is not a delta feed.
  Future<OrderFeed> fetchOrders() async {
    final res = await _client
        .get(_uri('/api/terminal/orders'), headers: _headers)
        .timeout(_timeout);
    if (res.statusCode == 401) throw const TerminalUnauthorized();
    if (res.statusCode != 200) {
      throw http.ClientException('orders ${res.statusCode}');
    }
    return OrderFeed.fromJson(_decode(res.body));
  }

  /// Today's orders, including the ones still on the board.
  ///
  /// Fetched on demand rather than polled: it is a screen someone opens, not an
  /// alarm, and adding it to the ten-second loop would triple the query load for
  /// a list nobody is looking at.
  Future<OrderHistory> fetchHistory() async {
    final res = await _client
        .get(_uri('/api/terminal/orders/history'), headers: _headers)
        .timeout(_timeout);
    if (res.statusCode == 401) throw const TerminalUnauthorized();
    if (res.statusCode != 200) {
      throw http.ClientException('history ${res.statusCode}');
    }
    return OrderHistory.fromJson(_decode(res.body));
  }

  /// Acknowledge — the alarm's only exit. Moves PENDING to CONFIRMED server-side.
  Future<void> acknowledge(int orderId) async {
    final res = await _client
        .post(_uri('/api/terminal/orders/$orderId/ack'), headers: _headers)
        .timeout(_timeout);
    if (res.statusCode == 401) throw const TerminalUnauthorized();
    if (res.statusCode >= 400) {
      throw http.ClientException('ack ${res.statusCode}');
    }
  }

  /// Move an order along the service path — Kochen, Fertig, Abgeholt.
  ///
  /// Returns the status the server actually holds, which is not always the one
  /// asked for: the path is forward-only, so a tap from a board that is a poll
  /// behind comes back with wherever the order really got to. That is a fact to
  /// display, not an error to report — the counter cares about the order, not
  /// about which screen won the race.
  Future<String> setStatus(int orderId, String status) async {
    final res = await _client
        .post(
          _uri('/api/terminal/orders/$orderId/status'),
          headers: _headers,
          body: jsonEncode({'status': status}),
        )
        .timeout(_timeout);
    if (res.statusCode == 401) throw const TerminalUnauthorized();

    final body = _decode(res.body);
    if (res.statusCode == 200 || res.statusCode == 409) {
      return body['status'] as String? ?? status;
    }
    throw http.ClientException('status ${res.statusCode}');
  }

  /// Tell the server where to send push for this device.
  ///
  /// Called on every launch rather than once. iOS reissues a device token after a
  /// restore, a reinstall, and sometimes for reasons of its own, and the app has
  /// no way to know which launch that happened on — so it re-registers every time
  /// and the server upserts.
  ///
  /// Returns whether it landed, and never throws on a network failure: push is the
  /// third channel after the poll and the shop's email, and failing a launch over
  /// it would trade a working tablet for a nicer notification.
  Future<bool> registerPushToken({
    required String deviceToken,
    required bool sandbox,
  }) async {
    try {
      final res = await _client
          .post(
            _uri('/api/terminal/push-token'),
            headers: _headers,
            body: jsonEncode({
              'token': deviceToken,
              // Which of Apple's two hosts this token belongs to. The app knows
              // and the server cannot: it is a property of the build, and a
              // debug build's token is rejected by the production host.
              'environment': sandbox ? 'sandbox' : 'production',
            }),
          )
          .timeout(_timeout);
      if (res.statusCode == 401) throw const TerminalUnauthorized();
      return res.statusCode == 200;
    } on TerminalUnauthorized {
      // Rethrown: a revoked terminal must reach the unpair path, the same as any
      // other 401. It is the only failure here that is not transient.
      rethrow;
    } catch (_) {
      return false;
    }
  }

  /// Stop sending push to this device.
  ///
  /// Called when unpairing. Without it a revoked tablet keeps being told about
  /// every order until Apple happens to reject the token, which for a device that
  /// still has the app installed is never.
  ///
  /// Best-effort for a different reason than the register call: unpairing must
  /// succeed locally even with no network, or a tablet being handed on cannot be
  /// wiped.
  Future<void> unregisterPushToken() async {
    try {
      await _client
          .delete(_uri('/api/terminal/push-token'), headers: _headers)
          .timeout(_timeout);
    } catch (_) {
      // Ignored. The server-side sweep for this is a 401 on the next push.
    }
  }

  Map<String, dynamic> _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      // A proxy error page instead of JSON is a normal thing to receive; it
      // should read as "request failed", not crash the poll loop.
      return <String, dynamic>{};
    }
  }

  void dispose() => _client.close();
}
