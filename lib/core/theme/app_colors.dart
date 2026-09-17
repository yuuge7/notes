import 'package:flutter/material.dart';
import 'package:notes/domain/model/pigment.dart';

/// A pigment resolved for one brightness: the spine drawn on the card's left
/// edge, and the tint washed behind the card.
@immutable
class PigmentSwatch {
  const PigmentSwatch({required this.spine, required this.tint});

  final Color spine;
  final Color tint;

  static PigmentSwatch lerp(PigmentSwatch a, PigmentSwatch b, double t) =>
      PigmentSwatch(
        spine: Color.lerp(a.spine, b.spine, t)!,
        tint: Color.lerp(a.tint, b.tint, t)!,
      );
}

/// Every colour in the app. Widgets read `Theme.of(context).colors`; no widget
/// declares a colour of its own.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.ground,
    required this.card,
    required this.ink,
    required this.inkMuted,
    required this.hairline,
    required this.accent,
    required this.onAccent,
    required this.accentWash,
    required this.mark,
    required this.danger,
    required this.viewer,
    required this.onViewer,
    required this.pigments,
  });

  /// Page background.
  final Color ground;

  /// Note surface, sheets, bars.
  final Color card;

  /// Primary text.
  final Color ink;

  /// Secondary text, icons at rest, meta.
  final Color inkMuted;

  /// Every border and rule in the app.
  final Color hairline;

  /// Actions, focus, selection.
  final Color accent;
  final Color onAccent;

  /// Accent at low opacity, for selected rows and chips.
  final Color accentWash;

  /// Behind the words a search matched: the accent laid on like a
  /// highlighter, strong enough to find on a tinted card.
  final Color mark;

  final Color danger;

  /// Behind a photo opened full screen, in both themes: near-black, so the
  /// photo is what shows rather than the page.
  final Color viewer;

  /// Controls and text laid over [viewer], and over a photo.
  final Color onViewer;

  final Map<Pigment, PigmentSwatch> pigments;

  PigmentSwatch swatch(Pigment pigment) => pigments[pigment]!;

  /// The card surface for [pigment]. Graphite keeps the plain paper card.
  Color surfaceFor(Pigment pigment) =>
      pigment.isNone ? card : pigments[pigment]!.tint;

  static const light = AppColors(
    ground: Color(0xFFF4F5F3),
    card: Color(0xFFFFFFFF),
    ink: Color(0xFF16181A),
    inkMuted: Color(0xFF5C6360),
    hairline: Color(0xFFE0E2DE),
    // A shade deeper than the verdigris pigment, so accent text holds 4.5:1
    // on every note tint and on the selected-row wash.
    accent: Color(0xFF28706D),
    onAccent: Color(0xFFFFFFFF),
    accentWash: Color(0x1A28706D),
    mark: Color(0x4028706D),
    danger: Color(0xFFB3402C),
    viewer: Color(0xFF0B0C0D),
    onViewer: Color(0xFFF1F3F2),
    pigments: {
      Pigment.graphite: PigmentSwatch(
        spine: Color(0x00000000),
        tint: Color(0xFFFFFFFF),
      ),
      Pigment.vermilion: PigmentSwatch(
        spine: Color(0xFFC9452E),
        tint: Color(0xFFFBEDE9),
      ),
      Pigment.amber: PigmentSwatch(
        spine: Color(0xFFB77A16),
        tint: Color(0xFFFBF3E2),
      ),
      Pigment.moss: PigmentSwatch(
        spine: Color(0xFF4F7A3A),
        tint: Color(0xFFEFF5EA),
      ),
      Pigment.verdigris: PigmentSwatch(
        spine: Color(0xFF2E7B78),
        tint: Color(0xFFE9F4F3),
      ),
      Pigment.indigo: PigmentSwatch(
        spine: Color(0xFF3D53A8),
        tint: Color(0xFFECEFFA),
      ),
      Pigment.plum: PigmentSwatch(
        spine: Color(0xFF7A3E86),
        tint: Color(0xFFF5EDF7),
      ),
      Pigment.clay: PigmentSwatch(
        spine: Color(0xFF8A5A44),
        tint: Color(0xFFF6EEE9),
      ),
    },
  );

  static const dark = AppColors(
    ground: Color(0xFF0F1113),
    card: Color(0xFF191C1E),
    ink: Color(0xFFE9EDEA),
    inkMuted: Color(0xFF9AA3A0),
    hairline: Color(0xFF262A2C),
    accent: Color(0xFF5FB3AE),
    onAccent: Color(0xFF06201F),
    accentWash: Color(0x265FB3AE),
    mark: Color(0x4D5FB3AE),
    danger: Color(0xFFE07A66),
    viewer: Color(0xFF050606),
    onViewer: Color(0xFFE9EDEA),
    pigments: {
      // Spines lift in dark so the edge still reads against a dark tint.
      Pigment.graphite: PigmentSwatch(
        spine: Color(0x00000000),
        tint: Color(0xFF191C1E),
      ),
      Pigment.vermilion: PigmentSwatch(
        spine: Color(0xFFE0705A),
        tint: Color(0xFF241614),
      ),
      Pigment.amber: PigmentSwatch(
        spine: Color(0xFFD69A38),
        tint: Color(0xFF221B10),
      ),
      Pigment.moss: PigmentSwatch(
        spine: Color(0xFF7FAE68),
        tint: Color(0xFF151E14),
      ),
      Pigment.verdigris: PigmentSwatch(
        spine: Color(0xFF5FB3AE),
        tint: Color(0xFF101F1E),
      ),
      Pigment.indigo: PigmentSwatch(
        spine: Color(0xFF7C8FD9),
        tint: Color(0xFF141827),
      ),
      Pigment.plum: PigmentSwatch(
        spine: Color(0xFFB47ABF),
        tint: Color(0xFF1F1424),
      ),
      Pigment.clay: PigmentSwatch(
        spine: Color(0xFFBA8871),
        tint: Color(0xFF201714),
      ),
    },
  );

  @override
  AppColors copyWith({
    Color? ground,
    Color? card,
    Color? ink,
    Color? inkMuted,
    Color? hairline,
    Color? accent,
    Color? onAccent,
    Color? accentWash,
    Color? mark,
    Color? danger,
    Color? viewer,
    Color? onViewer,
    Map<Pigment, PigmentSwatch>? pigments,
  }) {
    return AppColors(
      ground: ground ?? this.ground,
      card: card ?? this.card,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      hairline: hairline ?? this.hairline,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      accentWash: accentWash ?? this.accentWash,
      mark: mark ?? this.mark,
      danger: danger ?? this.danger,
      viewer: viewer ?? this.viewer,
      onViewer: onViewer ?? this.onViewer,
      pigments: pigments ?? this.pigments,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      ground: Color.lerp(ground, other.ground, t)!,
      card: Color.lerp(card, other.card, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      accentWash: Color.lerp(accentWash, other.accentWash, t)!,
      mark: Color.lerp(mark, other.mark, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      viewer: Color.lerp(viewer, other.viewer, t)!,
      onViewer: Color.lerp(onViewer, other.onViewer, t)!,
      pigments: {
        for (final pigment in Pigment.values)
          pigment: PigmentSwatch.lerp(
            pigments[pigment]!,
            other.pigments[pigment]!,
            t,
          ),
      },
    );
  }
}

extension AppColorsX on ThemeData {
  AppColors get colors => extension<AppColors>()!;
}
