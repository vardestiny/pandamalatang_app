import Flutter
import UIKit
import UserNotifications

/// The platform half of push. Its Dart counterpart is `lib/src/services/push.dart`.
///
/// No package and no pod: `UserNotifications` is a system framework, so the whole
/// APNs integration is this file plus the Push Notifications capability in Xcode.
/// The alternative was `firebase_messaging`, which brings a Firebase project, a
/// `GoogleService-Info.plist`, several pods and a second processor into the data
/// path of a shop whose privacy policy has to name its processors — for a
/// notification Apple was going to deliver either way.
///
/// The flow, worth stating because it is not the obvious one: a device token is not
/// returned by the call that asks for it. `registerForRemoteNotifications` returns
/// immediately and iOS answers later through a delegate callback — usually in well
/// under a second, sometimes never (no network, or the Simulator, which has no
/// APNs). So the Dart call's `FlutterResult` is parked in `pendingResult` and
/// fulfilled by whichever happens first: the token arrives, iOS reports a failure,
/// or the timeout fires. Every path answers exactly once. A `FlutterResult` invoked
/// twice is a hard crash; one never invoked hangs the Dart `await`, which in this
/// app means a tablet stuck on its loading spinner.
///
/// Note on `override`: the two `didRegister…`/`didFailToRegister…` methods and
/// `willPresent` are optional protocol methods that `FlutterAppDelegate` implements
/// in its `.mm` but does not declare in its public header, so Swift cannot see or
/// call them on `super`. Implementing them here therefore replaces Flutter's
/// forwarding of *those three callbacks* to plugins. Nothing in this app's plugin
/// list wants them (device_info_plus, audioplayers, shared_preferences, http), but
/// a future push-related plugin would need this revisited.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Must match `PushService.channelName` in Dart. A mismatch is a
  /// `MissingPluginException` at runtime and nothing at all at compile time.
  private static let channelName = "com.pandamalatang.terminal/push"

  /// Long enough for a slow shop connection, short enough that a tablet with no
  /// route to Apple is not left waiting on a spinner.
  private static let tokenTimeout: TimeInterval = 10

  private var channel: FlutterMethodChannel?

  /// The Dart caller waiting for a token, or nil when nobody is. Also how a double
  /// reply is prevented: every path nils it before answering.
  private var pendingResult: FlutterResult?

  /// Cached for the session. iOS returns the same token for a repeat registration
  /// within one launch, and this app re-registers whenever it resumes.
  private var deviceToken: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // So a notification arriving while someone is looking at the board is still
    // seen. Without this iOS suppresses the banner in the foreground, and the app
    // whose whole job is to be noticed is silent exactly when it is being watched.
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: AppDelegate.channelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(nil) }
      switch call.method {
      case "requestToken":
        self.requestToken(result: result)
      case "unregister":
        UIApplication.shared.unregisterForRemoteNotifications()
        self.deviceToken = nil
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  // MARK: - Token

  private func requestToken(result: @escaping FlutterResult) {
    if let token = deviceToken {
      return result(["token": token, "sandbox": AppDelegate.isSandbox])
    }

    // Someone is already waiting. Answer the newcomer with nothing rather than
    // overwriting the parked result, which would strand the earlier caller.
    if pendingResult != nil {
      return result([:])
    }

    UNUserNotificationCenter.current().requestAuthorization(
      options: [.alert, .sound, .badge]
    ) { [weak self] granted, error in
      // Back to the main queue: `UIApplication` and `FlutterResult` are both
      // main-thread only, and this completion block is on neither.
      DispatchQueue.main.async {
        guard let self = self else { return result([:]) }

        if let error = error {
          NSLog("push: authorization failed: \(error.localizedDescription)")
          return result([:])
        }
        guard granted else {
          // A refusal, not a failure. Dart reads an empty map as "no token" and
          // the tablet carries on with its ten-second poll.
          NSLog("push: notifications declined")
          return result([:])
        }

        self.pendingResult = result
        UIApplication.shared.registerForRemoteNotifications()

        DispatchQueue.main.asyncAfter(deadline: .now() + AppDelegate.tokenTimeout) {
          [weak self] in
          guard let pending = self?.pendingResult else { return }
          self?.pendingResult = nil
          NSLog("push: no device token within \(Int(AppDelegate.tokenTimeout))s")
          pending([:])
        }
      }
    }
  }

  func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken token: Data
  ) {
    // Hex, byte by byte. Apple's docs are explicit that the token is opaque bytes;
    // `token.description` produced usable hex for years and then stopped.
    let hex = token.map { String(format: "%02x", $0) }.joined()
    deviceToken = hex

    guard let pending = pendingResult else { return }
    pendingResult = nil
    pending(["token": hex, "sandbox": AppDelegate.isSandbox])
  }

  func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    // The common causes are both worth seeing in the log: no Push Notifications
    // capability on the target, and no network at first launch.
    NSLog("push: registration failed: \(error.localizedDescription)")

    guard let pending = pendingResult else { return }
    pendingResult = nil
    pending([:])
  }

  // MARK: - Environment

  /// Which of Apple's two APNs hosts this build's tokens are valid on.
  ///
  /// Read from the embedded provisioning profile rather than inferred from the build
  /// configuration, because the two disagree in a case that really happens: a
  /// Release build installed with a development profile — `flutter run --release` —
  /// is a release build whose tokens only work on sandbox.
  ///
  /// The server retries the other host and corrects the stored value anyway, so a
  /// wrong answer here costs one failed push rather than the shop's notifications.
  /// This is the cheap half of that belt and braces.
  private static let isSandbox: Bool = {
    #if DEBUG
      return true
    #else
      guard
        let url = Bundle.main.url(
          forResource: "embedded", withExtension: "mobileprovision"),
        let data = try? Data(contentsOf: url),
        // The profile is a CMS blob with a plist inside. isoLatin1 never fails on
        // arbitrary bytes, which is the point — utf8 would return nil here.
        let text = String(data: data, encoding: .isoLatin1),
        let key = text.range(of: "<key>aps-environment</key>")
      else {
        // Nothing to read means an App Store build, and those are production.
        return false
      }
      // Only what follows the key: "development" appears elsewhere in a
      // development profile's plist, so searching the whole text would always match.
      return text[key.upperBound...].prefix(120).contains("<string>development</string>")
    #endif
  }()
}

// MARK: - Foreground presentation

extension AppDelegate {
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler:
      @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // Banner and sound even in the foreground: the counter may be on the history
    // screen, or scrolled away from the new order on the board.
    completionHandler([.banner, .sound, .list])
  }
}
