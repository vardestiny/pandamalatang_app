# Panda Malatang — Terminal App

Plan of record. Flutter app for the shop's counter/kitchen tablet: it receives
orders from `pandamalatang.com` and makes a noise loud enough that nobody misses
one.

**Toolchain: always `fvm flutter`, never bare `flutter`.** Pinned in `.fvmrc`
(3.44.8 / Dart 3.12.2).

---

## Why this app exists

`PORT-PLAN.md` in the web repo records the biggest hole in the v1 operating model:
the admin order board polls every 20 seconds and the shop gets an email copy, but
**nothing makes a sound**. A busy counter that isn't watching the tablet misses an
order, and the customer finds out at pickup. This app closes that.

That framing drives every decision below: the alert is the product. Order display
is in service of it, and registration exists so the alert can be trusted to
arrive.

---

## 1. Transport: polling, not push

Poll `GET /api/terminal/orders?since=<cursor>` every 10 seconds.

Rejected push (FCM/APNs) for v1, deliberately:

- It needs a Firebase project, service credentials in Coolify, platform push
  certificates, and a delivery path that is silently throttled by the OS when it
  feels like it. For an alarm that must not be missed, "the OS decided to batch
  your notification" is a bad failure mode.
- The device is a plugged-in tablet on shop wifi, not a phone in a pocket. Battery
  and radio wake-ups are not a constraint.
- 10 seconds of latency on a pickup order that is 20 minutes out is irrelevant.

The cost is honest: if wifi drops, the app is blind. So the app shows connection
state permanently — last successful poll, and a visible warning once two polls in
a row fail. A terminal that has silently stopped receiving is worse than one that
says it has.

Push can be added later without changing the order model; it becomes a second
trigger for the same fetch. That is exactly what happened — see below. The poll
remains the transport; push exists only to make a noise while the app is away, and
the two are independent enough that either can fail alone.

### The hole this leaves: the app in the background

Requested 2026-08-01, and only half-closeable from Dart.

Backgrounded, the ten-second timer is at the OS's mercy. Android throttles it,
then dozes it, then may kill the process; iOS suspends the isolate within seconds.
So while the app is not in front, **no poll runs and nothing makes a noise** —
which is the failure this app was built to prevent, arrived at from a direction the
plan above did not consider. Nothing was ever posted to the notification shade
either, so even a poll that did land in a live background process had no way to
say so.

What is done: `OrderPoller` observes the app lifecycle and polls on `resumed`, so
returning to the app catches up instantly instead of showing a board up to ten
seconds stale. That fixes coming back. It does not tell anyone while they are away.

What telling them actually needs, and why it is not written yet — none of it can be
compiled on the current machine, which has **no Android SDK and no Xcode** (see
README): `flutter analyze`, `flutter test` and `flutter build web` all pass without
touching a line of it.

**Android — foreground service + local notification.** The right shape for this
product: a foreground service keeps the isolate and the poll alive indefinitely,
screen off included, and `flutter_local_notifications` posts a high-importance
notification when a new order lands. The service's own persistent notification is a
feature rather than a cost here — "the monitor is running" is exactly the thing §1
says a terminal must state out loud. Needs `POST_NOTIFICATIONS`,
`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`, a channel at alarm
importance, and a service declaration. No server change.

**iOS — push. Built 2026-08-01, and unfinished in one specific place.** The
suspended-app problem has no Dart answer, so the route is APNs, direct to Apple.
What exists now:

| | where | verified |
|---|---|---|
| Provider send | web repo `src/lib/apns.server.ts` | 26 tests, ES256 signature verified against a generated P-256 key |
| Token store | web repo `push_tokens` table + `/api/terminal/push-token` | 10 tests |
| Fired on order create | web repo `src/app/api/orders/route.ts`, ONLINE path only | `next build` passes |
| Dart half | `lib/src/services/push.dart`, `TerminalApi.registerPushToken` | 16 tests |
| Swift half | `ios/Runner/AppDelegate.swift` | **not compiled — no Xcode on this machine** |

**The Swift half has never been built.** It is authored against the Flutter 3.44
public headers (`FlutterImplicitEngineBridge.applicationRegistrar.messenger()`,
which is the current API and not the `window.rootViewController` cast most examples
still show), but the machine has Command Line Tools only — no Xcode, no CocoaPods —
so `flutter build ios` cannot run here. Treat that file as reviewed, not tested.

**What still has to be done in Xcode, by hand, once.** None of it is code:

1. Open `ios/Runner.xcworkspace` → Runner target → *Signing & Capabilities*.
2. `+ Capability` → **Push Notifications**. This is what creates
   `Runner.entitlements` with `aps-environment`, and no entitlements file is
   committed on purpose — Xcode wires the build setting at the same time, and a
   hand-written one drifts from `project.pbxproj`.
3. `+ Capability` → **Time Sensitive Notifications**, so
   `interruption-level: time-sensitive` is honoured rather than ignored.
4. On developer.apple.com, the App ID `com.pandamalatang.terminal` needs Push
   Notifications ticked, and the provisioning profile regenerated afterwards.
5. `pod install` in `ios/`, since CocoaPods has never run for this project.

No `UIBackgroundModes` entry is needed: these are alert pushes with
`apns-push-type: alert`, not silent content-available ones.

**Sandbox and production are different endpoints and different tokens** — and this
is handled rather than documented. A token from a debug build only delivers via
`api.sandbox.push.apple.com`, TestFlight and App Store builds only via
`api.push.apple.com`, and Apple returns the same opaque `400 BadDeviceToken` for
"wrong host" as for "nonsense token". So the server retries the other host and
persists the correction, and deletes the row only when both hosts reject it. Which
means `APNS_ENVIRONMENT` and the app's own reading of its provisioning profile are
both self-correcting, and a wrong guess costs one failed push rather than the shop's
notifications.

**Loud is still a separate application to Apple.** A normal push plays a sound of up
to 30 seconds and obeys silent mode and Do Not Disturb — it cannot loop, and it
cannot be the alarm §4 specifies. `interruption-level: time-sensitive` (set in the
payload, step 3 above) breaks through Focus and needs only the capability. An actual
looping, silent-switch-ignoring alarm needs **Critical Alerts**, which is a request
form to Apple and can be refused. So push supplements the in-app alarm; it does not
replace it. Worth settling before promising the shop that an iPad behaves like the
Android tablet, because on this point it does not.

**The payload carries no customer data**, asserted by a test rather than left to
discipline: "Neue Bestellung #K7F2QM · Abholung 18:30" is everything the counter
needs. A customer's name in the alert would make Apple a recipient of their personal
data and pull a section into the website's Datenschutzerklärung for the sake of a
nicer notification.

**Registration is re-done on every launch, not once.** iOS reissues a device token
after a restore or a reinstall and the app cannot know which launch that was, so it
re-registers each time and the server upserts. Unpair deletes server-side *and*
unregisters with the OS — without the first, a handed-on tablet keeps hearing about
this shop's orders until Apple happens to reject the token, which for a device that
still has the app installed is never.

**Android is still open.** Background push there means FCM, which means the Firebase
project and SDK this design exists to avoid; the alternative is a foreground service
(see above) which needs no server at all and posts a local notification. That is
still the better shape for an Android tablet, and still unbuildable here — no
Android SDK.

## 2. Device registration

A terminal is a first-class record in the backend, so the console can show which
devices exist and when each was last seen.

```
Terminal
  id, name            "Theke", "Küche"
  deviceLabel         model/OS the app reports, for identifying a lost tablet
  tokenHash           bcrypt of the bearer token — never the token itself
  pairingCode         6 chars, single use, null once redeemed
  pairingExpiresAt
  lastSeenAt          updated on every poll
  isActive            revoke without deleting the history
```

**Pairing flow**, chosen over a shared secret in the app:

1. Admin console → Terminals → *New terminal*, name it. Console shows a 6-character
   code valid for 15 minutes.
2. App, on first launch, asks for the code and a device name.
3. `POST /api/terminal/pair` `{ code, deviceLabel }` → returns a long-lived bearer
   token, once. The code is cleared.
4. Token goes into platform secure storage (Keychain / EncryptedSharedPreferences),
   not `SharedPreferences`.

A shared registration secret compiled into the app would be simpler and worse: it
cannot be revoked per device, it leaks with the APK, and it gives no audit trail.
A pairing code costs one admin screen and is revocable.

## 3. What the terminal shows

Two lists — **open** and **today** — on two screens rather than the one this plan
originally called for. The board stayed a single list of open orders, and today's
record moved behind the receipt icon in the app bar (`HistoryScreen`).

Reason: the board is a work queue read across a counter at arm's length, and a
second list under it pushes the open orders off the top of a tablet screen exactly
when there are most of them. The history is a different question, asked at a
different moment — a customer coming back with a code, or the till at closing time —
and it is fetched on the tap rather than added to the ten-second poll.

Today only, and no further back. Yesterday's takings are a reporting question for
the admin console, on a screen with a keyboard; bounding the tablet's view at one
shop-local day means no pagination, no date picker, and one request.

Each order card is a prep instruction, not a receipt — the same principle as the
web console's make ticket, and the same layout so staff moving between the two
are not relearning:

```
#1042   18:30   NEU
─────────────────────────────
🧋 2× Assam Milchtee   700 ml
      + Perlen, Käsecreme
🧋 1× Mango Dirty Milk 500 ml

🍲 €15,00 → ca. 500 g
   BRÜHE   Mala · SCHÄRFE MITTEL
   KOCHEN  Rindfleisch · Tofu · Enoki
   OHNE    ⚠ Koriander
   TOPPING Knoblauch · Sesam
─────────────────────────────
        [ Annehmen ]
```

Drinks first and bigger, because that is what this app is for. Size and add-ons
are on the same line as the drink, since a 700 ml with cheese cream and a 500 ml
without are different work. The size arrives as its own field on the feed
(`drinks[].size`) rather than being read out of the name — it lived in the name
until `strip-size-from-names` moved it into its own column for the website's size
toggle, and the ticket silently lost it.

The line total and the order total are on the card too, added after the fact. This
plan called the card "a prep instruction, not a receipt" and that is still the
layout — money sits at the bottom, under the prep — but payment happens at this
counter, at handover, so the number staff actually collect has to be on the screen
they are holding.

Exclusions keep the red warning treatment they have on the web ticket. That is
where allergies live and a miss has real consequences.

### The step button

One button per card, and it is the whole of what the terminal can do to an order:

```
NEU → [ Annehmen ] → ANGENOMMEN → [ Kochen ] → IN ARBEIT
    → [ Fertig ] → FERTIG → [ Abgeholt ] → off the board
```

The path, the words and the rule for walking it are the web console's, shared in
`@/lib/order-flow` on the backend: one member of staff uses both screens, often
within the same minute, and two definitions of "next" would eventually disagree
in front of a customer.

**Forward only.** A shop with two tablets will sooner or later have one showing a
board a poll behind, and a stale tap must not drag an order that is already
boiling back to "accepted". Skipping ahead is allowed — a counter that hands over
a drink it never marked as cooking is describing what actually happened.

**The tap shows immediately**, before the server answers, because the poll is ten
seconds and a card that does not react reads as a dead button. If the step fails
to reach the server it is taken back off the card and said out loud: unlike
silencing the alarm, a step nobody recorded is one the console, the kitchen and
the next shift will not know about.

**Abgeholt can be undone**, for eight seconds, from the toast that confirms it.
It is the only step that takes an order off the board, so it is the only misfire
a staff member cannot correct from the tablet — and the only backward move the
API permits. Cancelling is still the console's job: it needs a reason and a
decision about the customer's money.

## 4. The alert

The critical feature, so it is specified rather than left to taste.

**Trigger:** a poll returns an order the app has not seen.

**Behaviour:**

- Full-screen overlay, chilli red, order number at display size. It covers the app
  — not a toast, not a banner.
- Alarm sound on **loop**, at max app volume, and configured to ignore the iOS
  silent switch. A single beep is missable; a loop is not.
- Screen kept awake (`wakelock_plus`) so a sleeping tablet still lights up.
- **Only one way out: the Annehmen button.** No dismiss on tap-outside, no swipe,
  no back-button. This is the whole point — an alert that is easy to dismiss gets
  dismissed reflexively and the order is missed anyway.
- Acknowledging is meaningful, not cosmetic: it PATCHes the order to `CONFIRMED`,
  so the web console and the terminal agree on what has been seen.
- Several new orders at once queue into one overlay listing all of them, rather
  than stacking overlays that each need their own tap.

**Escalation:** if the alert is not acknowledged within 60 seconds, the sound gets
louder and the overlay starts flashing. A shop mid-rush is loud; the first pass
may genuinely not be heard.

## 5. Profile / settings

Not the point of the app, so it stays small: terminal name, when it paired, the
backend URL, last poll time, the **language**, a **test sound** button (so staff
can check the volume before service rather than during it), and unpair.

**Language: German, English, Chinese** — the three the web console already
speaks, using the console's own words for the domain terms (汤底 / BRÜHE / BROTH,
接单 / Annehmen / Accept). One member of staff reads both screens.

It follows the tablet by default and can be pinned in Profile. The pinned case is
the one that matters: shop equipment arrives set to whatever language it shipped
in, and the person reading it all shift is rarely the person who set it up. The
four choices are chips rather than a dropdown, each written in its own language —
somebody who has landed in a script they cannot read needs to spot their own
without first working out how to open a menu.

Two kinds of word, handled two different ways.

**The app's own** — statuses, spice, sugar, temperature, every label and button —
stay English enum names on the wire and are looked up on the device. A German
string sent from the server could not be shown to a tablet set to Chinese.

**The food's** — "Assam Milchtee", "Mala", "Koriander" — exist only in the menu,
so the app cannot translate them and does not try. It sends `Accept-Language`
with its resolved locale and the feed names each line in that language, from the
menu's own `name_de` / `name_en` / `name_zh` columns. The line's stored snapshot
is the fallback, for a menu item deleted while its order is still cooking.

That is a live lookup rather than a stored one, which is the opposite of what a
receipt should do and right here for the same reason: this board only shows
orders open right now, and a cook needs the ingredient named in a language they
can read. The snapshot stays the record of truth for the confirmation email, the
console's history and the reports. `l10n_ext.dart`
is where those lookups live, along with money (15,00 € / €15.00), dates, and the
one thing deliberately *not* localised — pickup times stay 24-hour everywhere,
because the console is 24-hour too and an am/pm slip is an order handed over an
hour late.

Test sound matters more than it looks: the failure mode of an alarm app is a muted
device, and the only way to catch that is to have made a noise on purpose.

## 6. Build order

1. Backend: `Terminal` model, migration, pair + orders + ack endpoints, admin
   Terminals screen. *(web repo)*
2. App skeleton: routing, secure storage, API client, connection banner.
3. Pairing screen.
4. Order list + detail cards.
5. **Alert overlay + looping sound + wakelock.**
6. Profile.

Steps 1–5 are the product. 6 is comfort.

## 7. Not in v1

Printing, cash handling, editing an order from the terminal, multi-shop, offline
queueing of acknowledgements, push notifications, staff-level accounts (the
terminal is the identity, not the person).

Weighing stays on the console too. The scale is there, the money is there, and a
handover from the tablet therefore records that the customer took the order and
nothing about what it finally weighed — which is the same thing the console's own
Abgeholt button does when no weights were typed.
