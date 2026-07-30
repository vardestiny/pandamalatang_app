import 'package:flutter/material.dart';

/// The shop's emblem.
///
/// One widget rather than an `Image.asset` at each call site, so the asset path
/// and the semantics label live in one place — and so the placeholders it
/// replaced (a 🐼 emoji on the pairing screen) cannot creep back in one screen at
/// a time.
///
/// The asset is transparent and is generated from the same original as the
/// website's logo — see ../../../pubspec.yaml and the generator it names.
class PandaLogo extends StatelessWidget {
  const PandaLogo({super.key, required this.height});

  final double height;

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/brand/logo-mark.png',
        height: height,
        // The emblem is decoration next to a heading that already names the shop,
        // so it is excluded from the accessibility tree rather than read out as a
        // second, redundant "Panda Malatang".
        excludeFromSemantics: true,
        // A missing asset would otherwise be a red error box filling the header of
        // a shop's order board. The app still works without its logo.
        errorBuilder: (_, _, _) => SizedBox(height: height),
      );
}
