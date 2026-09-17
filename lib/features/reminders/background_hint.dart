import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:notes/core/theme/app_colors.dart';
import 'package:notes/core/theme/tokens.dart';
import 'package:notes/core/theme/typography.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/features/reminders/reminder_providers.dart';

/// Says, once, that this maker's phones can stop the app in the background,
/// and its reminders with it, and opens the page that lets it run.
///
/// Shown on the reminders page and when a reminder is set, until it is acted
/// on or dismissed. Nothing shows on phones not known for it.
class BackgroundHint extends ConsumerWidget {
  const BackgroundHint({this.framed = true, super.key});

  /// A card of its own on a page, or plain lines inside a sheet.
  final bool framed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final maker = ref.watch(backgroundHintProvider).value;
    if (maker == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colors;

    Future<void> done() async {
      await ref.read(settingsRepositoryProvider).markBackgroundHintDone();
      ref.invalidate(backgroundHintProvider);
    }

    Future<void> open() async {
      await ref.read(phoneSystemProvider).openBackgroundSettings();
      await done();
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (framed) ...[
          Text(
            'MAY NOT RING WHILE CLOSED',
            style: AppText.metaStrong.copyWith(color: colors.inkMuted),
          ),
          const SizedBox(height: Gap.xs),
        ],
        Text(
          '$maker phones can stop Notes once it is closed, and its reminders '
          'with it. Let Notes run in the background so they ring.',
          style: AppText.ui.copyWith(
            color: framed ? colors.ink : colors.inkMuted,
          ),
        ),
        Wrap(
          spacing: Gap.lg,
          children: [
            TextButton(
              onPressed: () => unawaited(open()),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: const Text('Open settings'),
            ),
            TextButton(
              onPressed: () => unawaited(done()),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                foregroundColor: colors.inkMuted,
              ),
              child: const Text('Dismiss'),
            ),
          ],
        ),
      ],
    );

    if (!framed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.md, Gap.xl, 0),
        child: content,
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Layout.contentRight,
        0,
        Layout.contentRight,
        Gap.sm,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.card,
          border: Border.all(color: colors.hairline),
          borderRadius: BorderRadius.circular(Radii.card),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.xs),
          child: content,
        ),
      ),
    );
  }
}
