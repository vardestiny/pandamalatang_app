import 'package:flutter/material.dart';

/// The shop's palette, matched to the web front so the tablet does not look like
/// a different business.
abstract class PandaColors {
  static const chilli = Color(0xFFD7263D);
  static const chilliDeep = Color(0xFFA81C2E);
  static const ink = Color(0xFF241C17);
  static const inkSoft = Color(0xFF6B5E54);
  static const cream = Color(0xFFFDF6EC);
  static const creamDeep = Color(0xFFF4E7D4);
  static const paper = Color(0xFFFFFFFF);
  static const line = Color(0xFFE5D9C7);
  static const sichuan = Color(0xFF2F7D5B);
  static const amber = Color(0xFFE9A319);
}

ThemeData pandaTheme() {
  final base = ThemeData.light(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: PandaColors.cream,
    colorScheme: base.colorScheme.copyWith(
      primary: PandaColors.chilli,
      secondary: PandaColors.sichuan,
      surface: PandaColors.paper,
      onSurface: PandaColors.ink,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: PandaColors.ink,
      displayColor: PandaColors.ink,
    ),
    // Larger than a phone default throughout: this is read at arm's length on a
    // counter, often at a glance, sometimes by someone holding a cup.
    //
    // The scaling has to happen here rather than on `textTheme`, and the reason
    // is a trap worth writing down: `ThemeData.textTheme` carries colour and
    // weight but every `fontSize` in it is **null** at this point. Sizes live in
    // the script-specific geometry below, and Flutter only merges them in later,
    // once the locale is known. So `textTheme.apply(fontSizeFactor: …)` asserts
    // outright — "fontSize != null || (fontSizeFactor == 1.0 …)" — because it is
    // being asked to scale numbers that do not exist yet.
    //
    // All three geometries get the factor, not just englishLike, so a Chinese or
    // tall-script locale is scaled too instead of silently rendering at stock
    // size.
    typography: base.typography.copyWith(
      englishLike: base.typography.englishLike.apply(fontSizeFactor: 1.1),
      dense: base.typography.dense.apply(fontSizeFactor: 1.1),
      tall: base.typography.tall.apply(fontSizeFactor: 1.1),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: PandaColors.paper,
      foregroundColor: PandaColors.ink,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: PandaColors.chilli,
        foregroundColor: Colors.white,
        // Big hit areas: this gets pressed with a wet or gloved hand.
        minimumSize: const Size(0, 56),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
    ),
  );
}
