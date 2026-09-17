import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/core/theme/app_colors.dart';
import 'package:notes/core/theme/app_theme.dart';
import 'package:notes/core/theme/tokens.dart';
import 'package:notes/core/ui/page_transitions.dart';
import 'package:notes/domain/model/pigment.dart';

/// The design contract's rules that can be checked without drawing a frame:
/// contrast between the tokens, styles only from the tokens, and motion
/// under 300ms.
void main() {
  double luminance(Color color) {
    double channel(double c) =>
        c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(color.r) +
        0.7152 * channel(color.g) +
        0.0722 * channel(color.b);
  }

  double contrast(Color a, Color b) {
    final la = luminance(a);
    final lb = luminance(b);
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
  }

  for (final (name, colors) in [
    ('light', AppColors.light),
    ('dark', AppColors.dark),
  ]) {
    group('$name theme', () {
      final surfaces = {
        'ground': colors.ground,
        'card': colors.card,
        for (final pigment in Pigment.values)
          '${pigment.name} tint': colors.surfaceFor(pigment),
        // A selected drawer row or chip.
        'selected row': Color.alphaBlend(colors.accentWash, colors.ground),
      };

      for (final (text, color) in [
        ('ink', colors.ink),
        ('muted ink', colors.inkMuted),
        ('accent', colors.accent),
        ('danger', colors.danger),
      ]) {
        test('$text reads at 4.5:1 on every surface', () {
          for (final MapEntry(key: surface, value: background)
              in surfaces.entries) {
            expect(
              contrast(color, background),
              greaterThanOrEqualTo(4.5),
              reason: '$text on $surface',
            );
          }
        });
      }

      test('ink reads through a search highlight on every surface', () {
        for (final MapEntry(key: surface, value: background)
            in surfaces.entries) {
          expect(
            contrast(colors.ink, Color.alphaBlend(colors.mark, background)),
            greaterThanOrEqualTo(4.5),
            reason: surface,
          );
        }
      });

      test('text on filled buttons, the viewer, and the snackbar reads', () {
        final theme = name == 'light' ? AppTheme.light() : AppTheme.dark();
        final snackBar = theme.snackBarTheme;
        expect(
          contrast(colors.onAccent, colors.accent),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(colors.onAccent, colors.danger),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(colors.onViewer, colors.viewer),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(
            snackBar.contentTextStyle!.color!,
            snackBar.backgroundColor!,
          ),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(snackBar.actionTextColor!, snackBar.backgroundColor!),
          greaterThanOrEqualTo(4.5),
        );
      });
    });
  }

  group('motion', () {
    test('no token runs longer than 300ms', () {
      for (final duration in [
        Motion.container,
        Motion.page,
        Motion.standard,
        Motion.quick,
        Motion.reduced,
      ]) {
        expect(duration, lessThanOrEqualTo(const Duration(milliseconds: 300)));
      }
    });

    test('pages move within the limit too', () {
      final builder = AppTheme.light()
          .pageTransitionsTheme
          .builders[TargetPlatform.android];
      expect(builder, isA<AppPageTransitions>());
      expect(
        builder!.transitionDuration,
        lessThanOrEqualTo(const Duration(milliseconds: 300)),
      );
      expect(
        builder.reverseTransitionDuration,
        lessThanOrEqualTo(const Duration(milliseconds: 300)),
      );
    });
  });

  test('colours and font sizes come only from the theme tokens', () {
    // `Colors.transparent` is the absence of a colour, not a colour.
    final forbidden = RegExp(
      r'Color\(0x|Color\.fromARGB|Color\.fromRGBO|\bColors\.(?!transparent\b)\w+|fontSize:',
    );
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      final path = entity.path.replaceAll(r'\', '/');
      if (entity is! File ||
          !path.endsWith('.dart') ||
          path.endsWith('.g.dart') ||
          path.endsWith('.freezed.dart') ||
          path.startsWith('lib/core/theme/')) {
        continue;
      }
      for (final (index, line) in entity.readAsLinesSync().indexed) {
        if (line.trimLeft().startsWith('//')) continue;
        if (forbidden.hasMatch(line)) {
          offenders.add('$path:${index + 1}: ${line.trim()}');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
