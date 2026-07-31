import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Registering this tablet for push, so it hears about an order while the app is
/// in the background and the ten-second poll is not running.
///
/// Deliberately a bare `MethodChannel` and not `firebase_messaging`. APNs needs no
/// package at all — `UserNotifications` is a system framework, so this adds no pod,
/// no `pod install` step, and no second vendor in the data path of a shop whose
/// privacy policy has to name its processors. What it costs is about forty lines of
/// Swift in `AppDelegate.swift`, which is where the platform half lives.
///
/// Android is not wired up. It cannot be: Android background push means FCM, which
/// means a Firebase project and the SDK this file exists to avoid. `available` is
/// false there and everything below is a no-op, so the Android build keeps working
/// with the poll alone. See APP-PLAN §1.
class PushService {
  PushService({MethodChannel? channel, TargetPlatform? platform})
      : _channel = channel ?? const MethodChannel(channelName),
        _platform = platform ?? defaultTargetPlatform;

  /// Must match the string in `AppDelegate.swift`. A typo on either side is a
  /// `MissingPluginException` at runtime and nothing at compile time.
  static const channelName = 'com.pandamalatang.terminal/push';

  final MethodChannel _channel;
  final TargetPlatform _platform;

  /// iOS only — see the class comment.
  bool get available => _platform == TargetPlatform.iOS;

  /// Ask iOS for permission and, if granted, for a device token.
  ///
  /// Returns null when there is no token to register, which is a normal outcome and
  /// not an error: the user declined, the app is on the Simulator (which has no
  /// APNs), the device is offline, or this is Android. The caller carries on with
  /// the poll either way.
  ///
  /// Safe to call on every launch, and meant to be: iOS reissues a device token
  /// after a restore or a reinstall, and the app cannot know which launch that
  /// happened on.
  Future<PushToken?> requestToken() async {
    if (!available) return null;
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('requestToken');
      final token = result?['token'];
      if (token is! String || token.isEmpty) return null;
      return PushToken(
        token: token,
        // Reported by the native side from the app's own entitlement rather than
        // guessed from `kDebugMode`: a Release build signed with a development
        // profile is on sandbox, and a debug-mode guess would call it production.
        //
        // The server also self-corrects a wrong answer here by retrying the other
        // host, so this is belt and braces — but the belt costs one line.
        sandbox: result?['sandbox'] != false,
      );
    } on MissingPluginException {
      // The Swift half is not in this build. Worth failing quietly: it means push
      // is missing, not that the tablet cannot take orders.
      debugPrint('push: no platform implementation, notifications disabled');
      return null;
    } on PlatformException catch (e) {
      debugPrint('push: ${e.code} ${e.message}');
      return null;
    }
  }

  /// Turn off notifications for this device at the OS level.
  ///
  /// Called on unpair, alongside the server-side delete. Neither alone is enough:
  /// the server stops sending, and this stops the OS holding a registration for an
  /// app that is no longer this shop's tablet.
  Future<void> unregister() async {
    if (!available) return;
    try {
      await _channel.invokeMethod<void>('unregister');
    } catch (_) {
      // Best-effort. Unpairing must work with no network and no push.
    }
  }
}

/// A device token and the Apple host it is valid on.
@immutable
class PushToken {
  const PushToken({required this.token, required this.sandbox});

  final String token;

  /// True for a development build, whose token only delivers via
  /// `api.sandbox.push.apple.com`.
  final bool sandbox;

  @override
  bool operator ==(Object other) =>
      other is PushToken && other.token == token && other.sandbox == sandbox;

  @override
  int get hashCode => Object.hash(token, sandbox);

  /// Truncated on purpose. A device token is not a secret in the way the .p8 is,
  /// but it is a stable per-install identifier and a log is not the place for it.
  @override
  String toString() =>
      'PushToken(...${token.length > 8 ? token.substring(token.length - 8) : token}, '
      '${sandbox ? "sandbox" : "production"})';
}
