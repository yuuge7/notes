import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:notes/core/theme/app_colors.dart';
import 'package:notes/core/theme/tokens.dart';
import 'package:notes/core/theme/typography.dart';
import 'package:notes/domain/model/pigment.dart';

/// Asks for a note colour. Returns null when the sheet is dismissed.
///
/// Pass [current] to mark the note's colour; pass null when several notes
/// with different colours are being changed at once.
Future<Pigment?> showPigmentSheet(
  BuildContext context, {
  required Pigment? current,
}) {
  return showModalBottomSheet<Pigment>(
    context: context,
    builder: (_) => PigmentSheet(current: current),
  );
}

/// Eight named swatches. Each shows the colour the way a card does — a tint
/// inside, the spine colour as its edge — so the choice previews the result.
class PigmentSheet extends StatelessWidget {
  const PigmentSheet({required this.current, super.key});

  final Pigment? current;

  static const _perRow = 4;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    const pigments = Pigment.values;
    final rows = [
      for (var start = 0; start < pigments.length; start += _perRow)
        pigments.sublist(start, math.min(start + _perRow, pigments.length)),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                'COLOUR',
                style: AppText.metaStrong.copyWith(color: colors.inkMuted),
              ),
            ),
            const SizedBox(height: Gap.lg),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.sm),
                child: Row(
                  children: [
                    for (final pigment in row)
                      Expanded(
                        child: _Swatch(
                          pigment: pigment,
                          selected: pigment == current,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.pigment, required this.selected});

  final Pigment pigment;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    final edge = pigment.isNone
        ? colors.hairline
        : colors.swatch(pigment).spine;

    return Semantics(
      button: true,
      selected: selected,
      label: pigment.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(pigment),
        borderRadius: BorderRadius.circular(Radii.small),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.surfaceFor(pigment),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: edge,
                    width: pigment.isNone ? Stroke.hairline : Stroke.spine,
                  ),
                ),
                child: selected
                    ? Icon(Icons.check, size: 20, color: colors.ink)
                    : pigment.isNone
                    ? Icon(
                        Icons.format_color_reset_outlined,
                        size: 18,
                        color: colors.inkMuted,
                      )
                    : null,
              ),
              const SizedBox(height: Gap.sm),
              Text(
                pigment.label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.metaCompact.copyWith(
                  color: selected ? colors.ink : colors.inkMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
