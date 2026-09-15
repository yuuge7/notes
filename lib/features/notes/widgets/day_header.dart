import 'package:flutter/material.dart';
import 'package:notes/core/theme/app_colors.dart';
import 'package:notes/core/theme/tokens.dart';
import 'package:notes/core/theme/typography.dart';

/// The label that opens a day's section: a mono heading, a tick crossing the
/// time gutter, and a rule running out to the edge.
class DayHeader extends StatelessWidget {
  const DayHeader({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;

    return Semantics(
      header: true,
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            SizedBox(
              width: Layout.contentLeft,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: Layout.gutterX - Layout.tickWidth / 2,
                  ),
                  child: Container(
                    width: Layout.tickWidth,
                    height: Stroke.hairline,
                    color: colors.hairline,
                  ),
                ),
              ),
            ),
            Text(
              label,
              style: AppText.metaStrong.copyWith(color: colors.inkMuted),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Container(
                height: Stroke.hairline,
                color: colors.hairline,
              ),
            ),
            const SizedBox(width: Layout.contentRight),
          ],
        ),
      ),
    );
  }
}

/// The vertical hairline the day ticks hang from.
///
/// It fades at both ends so it reads as a continuing record rather than a
/// box drawn around the content.
class TimeGutter extends StatelessWidget {
  const TimeGutter({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    // A stretched row rather than an Align: the line must fill the height it
    // is given, and Align hands its child loose constraints that collapse a
    // 1px-wide box to zero height.
    return IgnorePointer(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(width: Layout.gutterX),
          SizedBox(
            width: Stroke.hairline,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    colors.hairline.withValues(alpha: 0),
                    colors.hairline,
                    colors.hairline,
                    colors.hairline.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.05, 0.88, 1],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
