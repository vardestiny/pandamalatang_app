import 'package:flutter/material.dart';

import 'credentials.dart';

/// Settings that change what the whole app looks like. Today that is the
/// language and nothing else.
///
/// Separate from [Credentials], which is storage: this is the in-memory value
/// the widget tree listens to, so a language change repaints every screen
/// instead of taking effect on the next launch.
class AppSettings extends ChangeNotifier {
  AppSettings([Credentials? credentials])
      : _credentials = credentials ?? Credentials();

  final Credentials _credentials;

  Locale? _locale;

  /// The chosen language, or null for "follow the device".
  Locale? get locale => _locale;

  Future<void> load() async {
    final code = await _credentials.localeCode();
    _locale = code == null ? null : Locale(code);
    notifyListeners();
  }

  /// Null hands the decision back to the device.
  ///
  /// Repaints first and writes second: the person who just tapped a language is
  /// watching the screen, not the disk.
  Future<void> setLocale(Locale? locale) async {
    _locale = locale;
    notifyListeners();
    await _credentials.setLocaleCode(locale?.languageCode);
  }
}
