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

class PairingFailed implements Exception {
  const PairingFailed(this.message);
  final String message;
  @override
  String toString() => message;
}

class TerminalApi {
  TerminalApi({required this.baseUrl, this.token, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final String? token;
  final http.Client _client;

  // Long enough for a slow shop connection, short enough that a hung request
  // does not stall the next poll behind it.
  static const _timeout = Duration(seconds: 15);

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
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
      throw const PairingFailed('Zu viele Versuche. Bitte später erneut.');
    }
    if (res.statusCode != 200 || body['token'] is! String) {
      throw const PairingFailed('Code ungültig oder abgelaufen.');
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
