import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the terminal keeps what it knows about itself.
///
/// The token goes in the Keychain / EncryptedSharedPreferences because it is a
/// long-lived credential for the shop's live order feed — anyone holding it can
/// read every customer's name and phone number. The non-secret settings sit in
/// SharedPreferences, which is a plain file, and that is fine for a base URL.
class Credentials {
  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _tokenKey = 'terminal_token';
  static const _nameKey = 'terminal_name';
  static const _baseUrlKey = 'base_url';
  static const _pairedAtKey = 'paired_at';

  static const defaultBaseUrl = 'https://pandamalatang.com';

  Future<String?> token() => _secure.read(key: _tokenKey);

  Future<void> save({
    required String token,
    required String terminalName,
    required String baseUrl,
  }) async {
    await _secure.write(key: _tokenKey, value: token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, terminalName);
    await prefs.setString(_baseUrlKey, baseUrl);
    await prefs.setString(_pairedAtKey, DateTime.now().toIso8601String());
  }

  /// Unpair. Clears the token but keeps the base URL, because the next pairing is
  /// almost certainly against the same server and retyping a URL on a tablet
  /// keyboard is a small misery.
  Future<void> clear() async {
    await _secure.delete(key: _tokenKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_nameKey);
    await prefs.remove(_pairedAtKey);
  }

  Future<String> baseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_baseUrlKey) ?? defaultBaseUrl;
  }

  Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, url);
  }

  Future<String?> terminalName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_nameKey);
  }

  Future<DateTime?> pairedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pairedAtKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }
}
