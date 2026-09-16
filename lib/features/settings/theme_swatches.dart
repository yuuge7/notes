import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:notes/core/theme/app_colors.dart';
import 'package:notes/core/theme/tokens.dart';
import 'package:notes/core/theme/typography.dart';
import 'package:notes/domain/model/pigment.dart';
import 'package:notes/domain/model/settings.dart';

/// The theme choice, shown rather than named: each option is a page in that
/// theme with a note on it, spine and all, drawn from the theme's own
/// colours. System default is split corner to corner, day above night.
class ThemeSwatches extends StatelessWidget {
  const ThemeSwatches({
    required this.current,
    required this.onChanged,
    super.key,
  });

  final ThemeChoice current;
  final ValueChanged<ThemeChoice> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, choice) in ThemeChoice.values.indexed) ...[
          if (index > 0) const SizedBox(width: Gap.md),
          Expanded(
            child: _Swatch(
              choice: choice,
              selected: choice == current,
              onTap: () => onChanged(choice),
            ),
          ),
        ],
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.choice,
    required this.selected,
    required this.onTap,
  });

  final ThemeChoice choice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;

    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      selected: selected,
      label: '${choice.label} theme',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.card),
        child: Padding(
          padding: const EdgeInsets.only(bottom: Gap.xs),
          child: Column(
            children: [
              AnimatedContainer(
                duration: Motion.of(context, Motion.quick),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.card),
                  border: Border.all(
                    color: selected ? colors.accent : colors.hairline,
                    width: selected ? Stroke.selected : Stroke.hairline,
                  ),
                ),
                padding: EdgeInsets.all(
                  selected ? Stroke.hairline : Stroke.selected,
                ),
                child: AspectRatio(
                  aspectRatio: 1.1,
                  child: CustomPaint(
                    painter: _PagePainter(
                      choice: choice,
                      radius: Radii.card - Stroke.selected,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Gap.sm),
              Text(
                choice.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: (selected ? AppText.uiStrong : AppText.ui).copyWith(
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

/// A page with one note on it, in light, dark, or both.
class _PagePainter extends CustomPainter {
  const _PagePainter({required this.choice, required this.radius});

  final ThemeChoice choice;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final page = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas
      ..save()
      ..clipRRect(page);
    switch (choice) {
      case ThemeChoice.light:
        _paintPage(canvas, size, AppColors.light);
      case ThemeChoice.dark:
        _paintPage(canvas, size, AppColors.dark);
      case ThemeChoice.system:
        _paintPage(canvas, size, AppColors.light);
        final night = ui.Path()
          ..moveTo(size.width, 0)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close();
        canvas
          ..save()
          ..clipPath(night);
        _paintPage(canvas, size, AppColors.dark);
        canvas.restore();
    }
    canvas.restore();
  }

  void _paintPage(Canvas canvas, Size size, AppColors colors) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.ground);

    final card = Rect.fromLTRB(
      size.width * 0.16,
      size.height * 0.2,
      size.width * 0.84,
      size.height * 0.8,
    );
    final cardShape = RRect.fromRectAndRadius(card, const Radius.circular(5));
    // The spine, as on a card in the grid.
    canvas
      ..drawRRect(cardShape, Paint()..color = colors.card)
      ..save()
      ..clipRRect(cardShape)
      ..drawRect(
        Rect.fromLTWH(card.left, card.top, Stroke.spine, card.height),
        Paint()..color = colors.swatch(Pigment.verdigris).spine,
      )
      ..restore()
      ..drawRRect(
        cardShape.deflate(Stroke.hairline / 2),
        Paint()
          ..color = colors.hairline
          ..style = PaintingStyle.stroke
          ..strokeWidth = Stroke.hairline,
      );

    final left = card.left + card.width * 0.16;
    final lineWidth = card.width * 0.72;
    final line = card.height * 0.09;
    void bar(double top, double widthFactor, Color color) => canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, lineWidth * widthFactor, line),
        Radius.circular(line / 2),
      ),
      Paint()..color = color,
    );

    bar(card.top + card.height * 0.2, 0.62, colors.ink);
    bar(card.top + card.height * 0.46, 1, colors.inkMuted);
    bar(card.top + card.height * 0.64, 0.78, colors.inkMuted);
  }

  @override
  bool shouldRepaint(_PagePainter oldDelegate) =>
      oldDelegate.choice != choice || oldDelegate.radius != radius;
}
