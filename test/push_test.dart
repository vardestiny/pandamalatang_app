import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandamalatang_terminal/src/api/terminal_api.dart';
import 'package:pandamalatang_terminal/src/services/push.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';

/// Push registration.
///
/// The Swift half cannot be exercised from a Dart test, so what is pinned here is
/// the boundary: every way the native side can fail or refuse must come back as
/// "no token" rather than as an exception, because the tablet still has to take
/// orders on an iPad where the user tapped "Don't Allow".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(PushService.channelName);
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Answers `requestToken` with [reply], or throws it if it is an Exception.
  void stubChannel(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) async => handler(call));
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('PushService', () {
    test('is iOS-only, and says so rather than pretending', () {
      expect(
        PushService(platform: TargetPlatform.iOS).available,
        isTrue,
      );
      // Android would need FCM. Claiming availability there would mean the app
      // reports push as working while nothing is ever delivered.
      expect(PushService(platform: TargetPlatform.android).available, isFalse);
    });

    test('does not touch the channel on a platform it does not support', () async {
      var called = false;
      stubChannel((_) {
        called = true;
        return null;
      });

      final result = await PushService(platform: TargetPlatform.android).requestToken();

      expect(result, isNull);
      // Not just "returns null": invoking a channel with no implementation throws
      // MissingPluginException, and swallowing it would hide a real iOS wiring bug.
      expect(called, isFalse);
    });

    test('returns the token and environment the native side reported', () async {
      stubChannel((call) {
        expect(call.method, 'requestToken');
        return {'token': 'abc123', 'sandbox': false};
      });

      final result = await PushService(platform: TargetPlatform.iOS).requestToken();

      expect(result, const PushToken(token: 'abc123', sandbox: false));
    });

    test('assumes sandbox when the native side did not say', () async {
      // Sandbox is the safe default: the server retries the other host anyway, and
      // guessing production for a debug build is the more common mistake.
      stubChannel((_) => {'token': 'abc123'});

      final result = await PushService(platform: TargetPlatform.iOS).requestToken();

      expect(result?.sandbox, isTrue);
    });

    test('returns null when the user declined', () async {
      // What the Swift half sends on a denied authorization request: no token, no
      // error. A refusal is a choice, not a failure.
      stubChannel((_) => <String, Object?>{});

      expect(await PushService(platform: TargetPlatform.iOS).requestToken(), isNull);
    });

    test('returns null on an empty token rather than registering one', () async {
      // Registering '' would be a 400 from the server on every launch.
      stubChannel((_) => {'token': ''});

      expect(await PushService(platform: TargetPlatform.iOS).requestToken(), isNull);
    });

    test('survives a build with no Swift half', () async {
      messenger.setMockMethodCallHandler(channel, null);

      // MissingPluginException is what a stale iOS project produces, and it must
      // not be what stops a shop opening. This is the test that would have caught
      // shipping the Dart half on its own.
      expect(await PushService(platform: TargetPlatform.iOS).requestToken(), isNull);
    });

    test('survives an error thrown by the platform', () async {
      stubChannel((_) => throw PlatformException(code: 'no_apns'));

      expect(await PushService(platform: TargetPlatform.iOS).requestToken(), isNull);
    });

    test('unregister never throws, so unpairing always completes', () async {
      stubChannel((_) => throw PlatformException(code: 'boom'));

      // A tablet being handed on must be wipeable with no network and a broken
      // channel. Anything thrown here would leave it paired.
      await PushService(platform: TargetPlatform.iOS).unregister();
    });

    test('does not log the whole token', () {
      const token = PushToken(token: 'aaaaaaaaaaaaaaaaaaaabbbbcccc1234', sandbox: true);

      // It is a stable per-install identifier, and debugPrint output ends up in
      // crash reports and screenshots.
      expect(token.toString(), isNot(contains('aaaa')));
      expect(token.toString(), contains('cccc1234'));
      expect(token.toString(), contains('sandbox'));
    });
  });

  group('TerminalApi push token', () {
    /// A client that records the request and answers with [status].
    ({http.Client client, List<http.Request> log}) recording(int status) {
      final log = <http.Request>[];
      final client = MockClient((request) async {
        log.add(request);
        return http.Response('{"ok":true}', status);
      });
      return (client: client, log: log);
    }

    test('sends the token and the environment the app is built for', () async {
      final r = recording(200);
      final api = TerminalApi(baseUrl: 'https://x.test', token: 'tk', client: r.client);

      final ok = await api.registerPushToken(deviceToken: 'abc', sandbox: true);

      expect(ok, isTrue);
      expect(r.log.single.url.path, '/api/terminal/push-token');
      expect(jsonDecode(r.log.single.body), {
        'token': 'abc',
        'environment': 'sandbox',
      });
      // Same bearer token as every other call — pairing is the only credential,
      // and it is what ties a push registration to one terminal.
      expect(r.log.single.headers['Authorization'], 'Bearer tk');
    });

    test('says production for a release build', () async {
      final r = recording(200);
      final api = TerminalApi(baseUrl: 'https://x.test', token: 'tk', client: r.client);

      await api.registerPushToken(deviceToken: 'abc', sandbox: false);

      expect(jsonDecode(r.log.single.body)['environment'], 'production');
    });

    test('reports failure without throwing', () async {
      final r = recording(500);
      final api = TerminalApi(baseUrl: 'https://x.test', token: 'tk', client: r.client);

      // Push is the third channel after the poll and the shop's email. A 500 here
      // must not stop the board from opening.
      expect(await api.registerPushToken(deviceToken: 'abc', sandbox: true), isFalse);
    });

    test('rethrows a 401 so a revoked terminal still reaches the unpair path',
        () async {
      final client = MockClient((_) async => http.Response('{}', 401));
      final api = TerminalApi(baseUrl: 'https://x.test', token: 'tk', client: client);

      // The one failure here that is not transient. Swallowing it would leave a
      // revoked tablet showing a board it can no longer refresh.
      expect(
        () => api.registerPushToken(deviceToken: 'abc', sandbox: true),
        throwsA(isA<TerminalUnauthorized>()),
      );
    });

    test('survives a dead network', () async {
      final client = MockClient((_) async => throw http.ClientException('offline'));
      final api = TerminalApi(baseUrl: 'https://x.test', token: 'tk', client: client);

      expect(await api.registerPushToken(deviceToken: 'abc', sandbox: true), isFalse);
    });

    test('unregister sends a DELETE and swallows the failure', () async {
      final log = <String>[];
      final client = MockClient((request) async {
        log.add(request.method);
        return http.Response('', 500);
      });
      final api = TerminalApi(baseUrl: 'https://x.test', token: 'tk', client: client);

      await api.unregisterPushToken();

      expect(log, ['DELETE']);
    });
  });
}
