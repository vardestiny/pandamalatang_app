# Panda Malatang — Terminal

Flutter app for the shop's counter/kitchen tablet. It pairs itself to
`pandamalatang.com` as a registered terminal, polls the order feed every 10
seconds, shows each order as a prep instruction, and — the reason it exists —
makes a noise loud enough that nobody misses one.

Design decisions and their reasoning live in [`APP-PLAN.md`](APP-PLAN.md). This
file is how you build and run it.

**Toolchain: always `fvm flutter`, never bare `flutter`.** The SDK is pinned in
`.fvmrc` to 3.44.8 / Dart 3.12.2. A bare `flutter` picks up whatever is on
`PATH`, which is how a build starts failing for reasons nothing to do with the
code.

---

## Build and run on iOS

### Before anything: what this machine is missing

Checked on this Mac just now — both of these are hard blockers, and they are why
**the app has never been built for iOS at all**:

| | state |
|---|---|
| Xcode | **not installed** — only Command Line Tools (`/Library/Developer/CommandLineTools`) |
| CocoaPods | **not installed** (`pod` not on `PATH`) |
| fvm + Flutter 3.44.8 | ✅ installed |

`flutter analyze` and `flutter test` pass today because they need neither. An
iOS build needs both. Nothing below has been executed here, so treat the first
run as the first real test.

### 1. Install Xcode

Full Xcode, from the App Store or <https://developer.apple.com/xcode/>. It is
~10 GB and the download is the slow part; start it first and read on.

Then point the toolchain at it and let it finish its own first-run setup:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
sudo xcodebuild -license accept
```

Install a simulator runtime while you're there: Xcode → Settings → Components →
iOS Simulator.

### 2. Install CocoaPods

```sh
brew install cocoapods
```

Prefer Homebrew over `sudo gem install cocoapods` on current macOS — the system
Ruby is the usual source of "installed it, still not found".

### 3. Verify, then fetch packages

```sh
fvm flutter doctor            # Xcode and CocoaPods rows must both be ✓
cd /Users/destiny/Workspace/panda_imbiss/pandamalatang_app
fvm flutter pub get
```

### 4. Run on the simulator first

```sh
open -a Simulator
fvm flutter devices           # copy the simulator's id
fvm flutter run -d <device-id>
```

`ios/Podfile` and `ios/Podfile.lock` are committed, so pods resolve to fixed
versions.

> **Run `pod install` before trusting a build.** The committed `Podfile.lock`
> lists only **one** pod (`flutter_secure_storage`), but this app has **seven**
> iOS plugins — `audioplayers_darwin`, `device_info_plus`, `package_info_plus`,
> `path_provider_foundation`, `shared_preferences_foundation` and `wakelock_plus`
> are all missing from it. `flutter build ios` regenerates the lock itself, so
> this heals on the next real build; the reason to care is that
> `audioplayers_darwin` **is the alarm**, and a build against an incomplete pod
> integration is one that runs perfectly and never makes a sound.
>
> ```sh
> cd ios && pod install && cd ..     # lock should then list 7 pods
> ```

What the simulator can and cannot tell you:

- ✅ it renders, it pairs, orders arrive, the board and alert overlay look right
- ✅ the alarm sound plays (through the Mac's speakers)
- ❌ the silent switch, the volume buttons, wakelock, and how loud it actually is
  in a noisy shop — all device-only, and all central to this app

### 5. Run on a real iPad

**Prepare the iPad:** plug in over USB, tap *Trust This Computer*, then enable
Settings → Privacy & Security → **Developer Mode** and reboot. iOS 16+ hides
connected devices from Xcode entirely until Developer Mode is on, and the
symptom is just an empty device list.

**Set up signing** — needed once, and only Xcode can do it:

```sh
open ios/Runner.xcworkspace
```

Select the **Runner** project → **Runner** target → *Signing & Capabilities* →
tick *Automatically manage signing* → choose your **Team** (sign in with your
Apple ID under Xcode → Settings → Accounts first).

Then:

```sh
fvm flutter run -d <device-id>              # debug, hot reload
fvm flutter run --release -d <device-id>    # what a shift should actually run on
```

> **The one that will bite you.** A **free** Apple ID gives you a 7-day
> provisioning profile. The app installs, works, and then simply refuses to
> launch a week later — mid-service, with no warning and nothing in the logs to
> explain it. A tablet that takes the shop's orders cannot be on a free profile.
> Get the **Apple Developer Program** membership (€99/year) before this goes on
> the counter; profiles then last a year and TestFlight becomes available.

### 6. Release build and getting it onto the shop's iPads

For two or three tablets, **TestFlight** is the least painful route — installs
over the air, updates without a cable, 90 days per build.

```sh
fvm flutter build ipa
```

That produces `build/ios/archive/Runner.xcarchive`. Upload it via Xcode →
Window → Organizer → *Distribute App*, or script it with
`fvm flutter build ipa --export-options-plist=<plist>` once you know which
method you want (`app-store-connect` for TestFlight, `ad-hoc` for direct
install on pre-registered devices).

Bump `version:` in `pubspec.yaml` for each upload — App Store Connect rejects a
build number it has already seen.

### iOS settings already in place

Verified in the project, so you don't need to touch them:

- **Bundle ID** `com.pandamalatang.terminal`
- **Deployment target iOS 13.0** — matches the highest plugin requirement
  (`audioplayers_darwin` and `shared_preferences_foundation` both need 13.0), so
  pods will resolve
- **Display name** "Pandamalatang Terminal"
- **Orientations** all four on iPad — a wall mount can be either way up
- **Silent switch ignored**: the alarm uses `AVAudioSessionCategory.playback`
  rather than `ambient` (`lib/src/services/alarm.dart`). A mute toggle nobody
  remembers flicking must not be able to disable the order alarm
- Keychain needs no entitlement on iOS, so `flutter_secure_storage` works as-is

### One iOS decision left to you

**Background audio is not enabled.** The alarm sounds only while the app is in
the foreground. If a staff member switches to Safari, an incoming order arrives
silently.

Two ways to close it, and I did not pick for you because they are different
trade-offs:

1. **Lock the tablet to the app** — Settings → Accessibility → **Guided Access**,
   triple-click to exit. No code change, no App Store implications, and a shop
   terminal arguably shouldn't run anything else anyway. My recommendation.
2. **Allow audio in the background** — add to `ios/Runner/Info.plist`:

   ```xml
   <key>UIBackgroundModes</key>
   <array><string>audio</string></array>
   ```

   Works regardless of what's on screen, but Apple asks what you use it for at
   review time, and "alarm" is a weaker answer than "music player".

Also worth setting on the device itself: Settings → Display & Brightness →
**Auto-Lock → Never**. `wakelock_plus` holds the screen awake while the app is
open, but Auto-Lock: Never removes the question entirely.

---

## Build and run on Android

Same code, and the alarm routes to Android's **alarm stream** so Do Not Disturb
doesn't silence it. But **there is no Android SDK on this machine either**, so no
APK has ever been produced.

```sh
# after installing Android Studio and letting it fetch the SDK
fvm flutter doctor
fvm flutter build apk --release      # build/app/outputs/flutter-apk/app-release.apk
fvm flutter install                  # onto a connected device
```

For a shop tablet, also pin the app (Settings → Security → App pinning) so it
can't be swiped away mid-service.

---

## First run: pairing the terminal

The app ships with no credentials. It earns them once, from the console.

1. **Admin console** → `/admin/terminals` → *Neues Terminal*, name it (`Theke`,
   `Küche`). The console shows a **6-character code, valid 15 minutes, single
   use**.
2. **App**, first launch: enter the code. The server URL defaults to
   `https://pandamalatang.com` and only needs changing to test against a
   different backend.
3. The app exchanges the code for a bearer token and stores it in the
   **Keychain**. The server keeps only a hash — the token is shown exactly once
   and genuinely cannot be recovered, which is also the revocation story.

**Re-pair or revoke** from `/admin/terminals`. Both clear the stored token
server-side, so revoked means *stops receiving orders*, not just *looks revoked
in a list*.

**Before every service:** Profile → **Ton testen**. The failure mode of an alarm
app is a device someone turned down, and the only way to catch that is to make a
noise on purpose beforehand rather than discover it during a rush.

---

## Everyday commands

```sh
fvm flutter pub get           # after any pubspec change
fvm flutter analyze           # clean
fvm flutter test              # 9 tests, all passing
fvm flutter run -d <id>       # r = hot reload, R = restart, q = quit
fvm flutter clean             # when a build fails for no visible reason
```

The tests are worth knowing about: they cover the logic that decides what counts
as a *new* order, which is the part that would fail quietly and expensively.
"New" is the app's judgement, not the server's — the feed returns everything
open and the app diffs against the ids it has already seen, so a tablet that was
asleep or offline catches up instead of having missed the alert. The first poll
after launch seeds that set **without** alarming; otherwise every restart
screams about the whole board and staff learn to ignore it.

---

## What's where

```
lib/
  main.dart                     boot; decides pairing vs. board, owns poller + alarm
  src/
    api/terminal_api.dart       pair / fetch orders / acknowledge
    models/order.dart           order, drink lines with add-ons, bowls
    services/
      credentials.dart          token → Keychain, settings → SharedPreferences
      order_poller.dart         the 10s loop and what counts as "new"
      alarm.dart                looping sound, silent-switch override, escalation
    screens/
      pairing_screen.dart       code entry
      board_screen.dart         open + done-today, connection state
      alert_overlay.dart        the full-screen alarm
      profile_screen.dart       identity, test sound, unpair
    widgets/order_card.dart     the prep instruction
    theme.dart
assets/sounds/new_order.wav     two-tone chirp with a gap, so a loop is audible as a loop
test/order_poller_test.dart     9 tests
```

Backend side, in the `pangdamalatang` repo:
`src/app/api/terminal/{pair,orders}` and `orders/[id]/ack`, plus the admin
screen at `src/app/admin/(protected)/terminals/`.

---

## Known gaps

Stated plainly, because some of these matter more than they look:

- **Never run on a device from this machine.** Still no Xcode and no Android SDK
  here, so `analyze` and the tests are the whole of what gets verified locally.
- **The alarm has never actually sounded** end-to-end from a real order. The API
  path is verified against production; the noise is not.
- **`Podfile.lock` is incomplete** — see the warning above; run `pod install`.
- **`macos/` and `web/` exist** from a `flutter create` run and are untracked.
  Handy for checking layout without a tablet, but neither reproduces the alarm's
  real behaviour (silent switch, alarm stream, wakelock).
- **Polling, not push.** If wifi drops the app is blind, so it shows connection
  state permanently and warns after two consecutive failed polls. A terminal
  that has silently stopped receiving looks exactly like a quiet shop, and that
  is the failure this app exists to prevent.
- **Foreground-only alarm** — see the iOS decision above.
- **German-only UI.** The console is trilingual; this app is not. Deliberate for
  v1: the terminal has one audience standing in one kitchen.
