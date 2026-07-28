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
trigger for the same fetch.

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

Two lists, one screen: **open** and **done today**. Open is what matters.

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
without are different work.

Exclusions keep the red warning treatment they have on the web ticket. That is
where allergies live and a miss has real consequences.

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
backend URL, last poll time, a **test sound** button (so staff can check the
volume before service rather than during it), and unpair.

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
