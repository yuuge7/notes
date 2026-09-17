import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/core/theme/app_colors.dart';
import 'package:notes/domain/model/pigment.dart';

/// The colours Android draws with before Flutter runs, and in the home screen
/// widgets, where Flutter never runs: copies of the theme's tokens, which must
/// not drift from them.
void main() {
  Map<String, Color> colorsIn(String folder) {
    final xml = File('android/app/src/main/res/$folder/colors.xml')
        .readAsStringSync();
    return {
      for (final match in RegExp(
        r'<color name="(\w+)">#([0-9A-Fa-f]{6,8})</color>',
      ).allMatches(xml))
        match.group(1)!: Color(
          int.parse(
            match.group(2)!.length == 6
                ? 'FF${match.group(2)}'
                : match.group(2)!,
            radix: 16,
          ),
        ),
    };
  }

  for (final (folder, theme) in [
    ('values', AppColors.light),
    ('values-night', AppColors.dark),
  ]) {
    test(
      '$folder/colors.xml matches the ${folder == 'values' ? 'light' : 'dark'} theme',
      () {
        final android = colorsIn(folder);

        expect(android['ground'], theme.ground);
        expect(android['card'], theme.card);
        expect(android['ink'], theme.ink);
        expect(android['ink_muted'], theme.inkMuted);
        expect(android['hairline'], theme.hairline);
        expect(android['accent'], theme.accent);
        for (final pigment in Pigment.values.where((p) => !p.isNone)) {
          expect(
            android['spine_${pigment.name}'],
            theme.swatch(pigment).spine,
            reason: '${pigment.name} spine',
          );
          expect(
            android['tint_${pigment.name}'],
            theme.swatch(pigment).tint,
            reason: '${pigment.name} tint',
          );
        }
      },
    );
  }

  test('every pigment has a widget card', () {
    for (final pigment in Pigment.values) {
      expect(
        File(
          'android/app/src/main/res/drawable/widget_card_${pigment.name}.xml',
        ).existsSync(),
        isTrue,
        reason: pigment.name,
      );
    }
  });
}
