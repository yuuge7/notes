import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:notes/core/theme/app_colors.dart';
import 'package:notes/core/theme/tokens.dart';
import 'package:notes/core/theme/typography.dart';

/// Shared frame for the states a shelf can be in.
class StateMessage extends StatelessWidget {
  const StateMessage({
    required this.eyebrow,
    required this.headline,
    required this.body,
    this.action,
    super.key,
  });

  final String eyebrow;
  final String headline;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              eyebrow,
              style: AppText.metaStrong.copyWith(color: colors.inkMuted),
            ),
            const SizedBox(height: Gap.md),
            Text(
              headline,
              style: AppText.display.copyWith(color: colors.ink),
            ),
            const SizedBox(height: Gap.sm),
            Text(
              body,
              style: AppText.noteBody.copyWith(color: colors.inkMuted),
            ),
            if (action != null) ...[
              const SizedBox(height: Gap.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Nothing captured yet. The compose bar below is the invitation, so this
/// screen points at it instead of repeating a button.
class NotesEmpty extends StatelessWidget {
  const NotesEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    return const StateMessage(
      eyebrow: 'NOTHING CAPTURED',
      headline: 'Your notes start here',
      body: 'Tap Take a note to write the first one. It saves as you type.',
    );
  }
}

/// A label no note on the grid wears yet. The compose bar below writes notes
/// that wear it, so that is the invitation.
class LabelEmpty extends StatelessWidget {
  const LabelEmpty({required this.name, super.key});

  final String name;

  @override
  Widget build(BuildContext context) {
    return StateMessage(
      eyebrow: 'LABEL',
      headline: 'Nothing here yet',
      body:
          'A note written here wears “$name” from the start. Archived notes '
          'keep their labels and turn up in search.',
    );
  }
}

class ArchiveEmpty extends StatelessWidget {
  const ArchiveEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    return const StateMessage(
      eyebrow: 'ARCHIVE',
      headline: 'Nothing archived',
      body: 'Archived notes leave the grid but keep their labels and reminders.',
    );
  }
}

class TrashEmpty extends StatelessWidget {
  const TrashEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    return const StateMessage(
      eyebrow: 'TRASH',
      headline: 'Trash is empty',
      body: 'Deleted notes wait here for seven days before they are removed.',
    );
  }
}

/// The read failed. Say what happened and offer the one useful move.
class NotesError extends StatelessWidget {
  const NotesError({required this.onRetry, this.detail, super.key});

  final VoidCallback onRetry;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return StateMessage(
      eyebrow: 'NOTES DID NOT LOAD',
      headline: 'The notebook stayed shut',
      body: detail == null
          ? 'The database refused to open. Your notes are still on the device.'
          : 'The database refused to open: $detail',
      action: FilledButton(onPressed: onRetry, child: const Text('Try again')),
    );
  }
}

/// Placeholder cards while the first read runs.
///
/// Cards, not a spinner: the shape of what is coming is more useful than a
/// rotating disc, and the grid does not jump when the notes arrive.
class NotesSkeleton extends StatefulWidget {
  const NotesSkeleton({required this.columns, super.key});

  final int columns;

  @override
  State<NotesSkeleton> createState() => _NotesSkeletonState();
}

class _NotesSkeletonState extends State<NotesSkeleton>
    with SingleTickerProviderStateMixin {
  static const _heights = [128.0, 96.0, 172.0, 112.0, 88.0, 144.0];

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;

    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(
          left: Layout.contentLeft,
          right: Layout.contentRight,
          top: Gap.sm,
        ),
        child: MasonryGridView.count(
          crossAxisCount: widget.columns,
          mainAxisSpacing: Layout.cardGap,
          crossAxisSpacing: Layout.cardGap,
          itemCount: _heights.length,
          physics: const NeverScrollableScrollPhysics(),
          itemBuilder: (context, index) => FadeTransition(
            opacity: Tween<double>(begin: 0.45, end: 0.9).animate(_pulse),
            child: Container(
              height: _heights[index % _heights.length],
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(Radii.card),
                border: Border.all(color: colors.hairline),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
