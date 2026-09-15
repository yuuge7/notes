import 'package:flutter/material.dart';

/// Three faces, three jobs.
///
/// Literata carries note content: it is a reading face, so a note looks like
/// something written rather than something rendered. Schibsted Grotesk runs
/// the interface. Martian Mono is reserved for meta — timestamps, day headers,
/// counts — which is what makes the time gutter read as a record rather than
/// as decoration. Nothing else uses mono.
abstract final class Faces {
  static const String reading = 'Literata';
  static const String ui = 'SchibstedGrotesk';
  static const String meta = 'MartianMono';
}

List<FontVariation> _reading(double weight, double opticalSize) => [
  FontVariation('opsz', opticalSize),
  FontVariation('wght', weight),
];

List<FontVariation> _ui(double weight) => [FontVariation('wght', weight)];

List<FontVariation> _meta(double weight, {double width = 100}) => [
  FontVariation('wdth', width),
  FontVariation('wght', weight),
];

abstract final class AppText {
  /// Screen titles.
  static const display = TextStyle(
    fontFamily: Faces.reading,
    fontSize: 28,
    height: 32 / 28,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('opsz', 28), FontVariation('wght', 600)],
    letterSpacing: -0.3,
  );

  /// Note title on a card and in the editor.
  static const noteTitle = TextStyle(
    fontFamily: Faces.reading,
    fontSize: 17,
    height: 22 / 17,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('opsz', 17), FontVariation('wght', 600)],
    letterSpacing: -0.1,
  );

  /// Note body on a card.
  static const noteBody = TextStyle(
    fontFamily: Faces.reading,
    fontSize: 15,
    height: 22 / 15,
    fontVariations: [FontVariation('opsz', 15), FontVariation('wght', 400)],
  );

  /// Note body while writing. Longer measure, more air.
  static const noteBodyEditor = TextStyle(
    fontFamily: Faces.reading,
    fontSize: 16,
    height: 26 / 16,
    fontVariations: [FontVariation('opsz', 16), FontVariation('wght', 400)],
  );

  static const noteTitleEditor = TextStyle(
    fontFamily: Faces.reading,
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('opsz', 22), FontVariation('wght', 600)],
    letterSpacing: -0.2,
  );

  /// Buttons, chips, drawer, everything interactive.
  static const ui = TextStyle(
    fontFamily: Faces.ui,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w500,
    fontVariations: [FontVariation('wght', 500)],
  );

  static const uiStrong = TextStyle(
    fontFamily: Faces.ui,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
  );

  static const uiLarge = TextStyle(
    fontFamily: Faces.ui,
    fontSize: 16,
    height: 22 / 16,
    fontWeight: FontWeight.w500,
    fontVariations: [FontVariation('wght', 500)],
  );

  /// Timestamps, counts, day headers. Uppercase is applied at the call site.
  static const meta = TextStyle(
    fontFamily: Faces.meta,
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wdth', 100), FontVariation('wght', 400)],
    letterSpacing: 0.44,
  );

  /// Meta inside a card, where width is scarce: chips, capture time, counts.
  /// Same face and size, condensed on Martian Mono's own width axis, so a
  /// narrow card keeps its footer on one line without shrinking the text.
  static const metaCompact = TextStyle(
    fontFamily: Faces.meta,
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wdth', 75), FontVariation('wght', 400)],
    letterSpacing: 0.22,
  );

  static const metaStrong = TextStyle(
    fontFamily: Faces.meta,
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wdth', 100), FontVariation('wght', 600)],
    letterSpacing: 0.44,
  );

  static TextStyle reading(double size, double weight, {double? height}) =>
      TextStyle(
        fontFamily: Faces.reading,
        fontSize: size,
        height: height,
        fontVariations: _reading(weight, size),
      );

  static TextStyle interface(double size, double weight, {double? height}) =>
      TextStyle(
        fontFamily: Faces.ui,
        fontSize: size,
        height: height,
        fontVariations: _ui(weight),
      );

  static TextStyle metric(double size, double weight, {double width = 100}) =>
      TextStyle(
        fontFamily: Faces.meta,
        fontSize: size,
        fontVariations: _meta(weight, width: width),
        letterSpacing: size * 0.04,
      );
}
