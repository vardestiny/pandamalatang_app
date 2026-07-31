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
/// Note on `override`: `FlutterAppDelegate` implements all three delegate callbacks
/// below, so each needs the keyword even though none of them appears in the public
/// header — the compiler sees them through the Objective-C interface. The two
/// `didRegister…` ones call `super`, which is how Flutter forwards them to plugins
/// that also want the device token. `willPresent` deliberately does not: Flutter's
/// implementation invokes the completion handler itself, and a completion handler
/// invoked twice is a crash. It also has to live in the class body rather than in an
/// extension, because Swift cannot override from one.
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

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken token: Data
  ) {
    // Hex, byte by byte. Apple's docs are explicit that the token is opaque bytes;
    // `token.description` produced usable hex for years and then stopped.
    let hex = token.map { String(format: "%02x", $0) }.joined()
    deviceToken = hex

    if let pending = pendingResult {
      pendingResult = nil
      pending(["token": hex, "sandbox": AppDelegate.isSandbox])
    }

    // Still forwarded: this is how Flutter passes the token to any plugin that also
    // registered for it, and swallowing it would quietly break one added later.
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: token)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    // The common causes are both worth seeing in the log: no Push Notifications
    // capability on the target, and no network at first launch.
    NSLog("push: registration failed: \(error.localizedDescription)")

    if let pending = pendingResult {
      pendingResult = nil
      pending([:])
    }

    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  // MARK: - Foreground presentation

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler:
      @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // Shown and sounded even in the foreground: the counter may be on the history
    // screen, or scrolled away from the new order on the board. iOS suppresses the
    // banner by default while an app is in front, which is exactly the moment this
    // app is being watched.
    //
    // No `super` call. Flutter's implementation invokes the completion handler
    // itself, and invoking one twice is a hard crash.
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .sound, .list])
    } else {
      // `.alert` is what iOS 13 has; iOS 14 split it into `.banner` and `.list`.
      // The deployment target is still 13.0, so both branches have to exist.
      completionHandler([.alert, .sound])
    }
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
