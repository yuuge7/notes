import 'package:flutter/widgets.dart';

/// Spacing scale. Everything in the app steps through these values.
abstract final class Gap {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner radii. Cards are gently rounded, sheets more so, chips fully.
abstract final class Radii {
  static const double small = 8;
  static const double card = 14;
  static const double bar = 16;
  static const double sheet = 24;
  static const double chip = 999;
}

/// Line weights. The interface is drawn with hairlines, not shadows.
abstract final class Stroke {
  static const double hairline = 1;
  static const double spine = 3;
  static const double selected = 2;
}

/// Layout constants for the notes grid and its gutter.
abstract final class Layout {
  /// Distance from the screen edge to the vertical time gutter.
  static const double gutterX = 9;

  /// Left edge of content. Leaves the gutter its own margin.
  static const double contentLeft = 20;
  static const double contentRight = Gap.lg;

  /// Length of the tick that crosses the gutter at a day header.
  static const double tickWidth = 9;

  static const double cardGap = Gap.md;
  static const double composeBarHeight = 52;
}

/// Motion. Nothing runs longer than 300ms, and everything collapses to a fast
/// cross-fade when the platform asks for reduced motion.
abstract final class Motion {
  static const Duration container = Duration(milliseconds: 220);
  static const Duration standard = Duration(milliseconds: 180);
  static const Duration quick = Duration(milliseconds: 140);
  static const Duration reduced = Duration(milliseconds: 80);

  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;

  /// [duration], or the reduced-motion equivalent when the user asked for it.
  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context)
          ? (duration < reduced ? duration : reduced)
          : duration;
}
