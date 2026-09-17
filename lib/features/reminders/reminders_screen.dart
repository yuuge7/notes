import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:notes/core/theme/app_colors.dart';
import 'package:notes/core/theme/tokens.dart';
import 'package:notes/core/theme/typography.dart';
import 'package:notes/core/ui/masonry.dart';
import 'package:notes/core/ui/shelf_scaffold.dart';
import 'package:notes/core/util/reminder_time.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/domain/model/note.dart';
import 'package:notes/domain/service/reminder_scheduler.dart';
import 'package:notes/features/notes/notes_providers.dart';
import 'package:notes/features/notes/notes_screen.dart';
import 'package:notes/features/notes/widgets/app_drawer.dart';
import 'package:notes/features/notes/widgets/day_header.dart';
import 'package:notes/features/notes/widgets/note_tile.dart';
import 'package:notes/features/notes/widgets/notes_states.dart';
import 'package:notes/features/reminders/background_hint.dart';
import 'package:notes/features/reminders/reminder_providers.dart';
import 'package:notes/features/shelf/shelf_screen.dart';

/// Reminders in the order they matter: overdue ones, oldest first, then the
/// rest of today, then everything after. Finished one-off reminders are left
/// out.
List<(String, List<Note>)> groupReminders(
  List<Note> notes, {
  required DateTime now,
}) {
  final overdue = <(DateTime, Note)>[];
  final today = <(DateTime, Note)>[];
  final upcoming = <(DateTime, Note)>[];
  for (final note in notes) {
    final at = note.reminderAt;
    if (at == null || note.reminderDone || note.deleted) continue;
    final next = ReminderTime.next(at, note.reminderRule, now);
    if (note.reminderRule == null && !next.isAfter(now)) {
      overdue.add((next, note));
    } else if (next.year == now.year &&
        next.month == now.month &&
        next.day == now.day) {
      today.add((next, note));
    } else {
      upcoming.add((next, note));
    }
  }

  List<Note> sorted(List<(DateTime, Note)> group) => [
    for (final (_, note) in group..sort((a, b) => a.$1.compareTo(b.$1))) note,
  ];

  return [
    if (overdue.isNotEmpty) ('OVERDUE', sorted(overdue)),
    if (today.isNotEmpty) ('TODAY', sorted(today)),
    if (upcoming.isNotEmpty) ('UPCOMING', sorted(upcoming)),
  ];
}

/// Every note waiting to ring, reached from the drawer.
class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(reminderNotesProvider);
    final access = ref.watch(reminderAccessProvider).value;
    final columns = NotesScreen.columnsFor(ref.watch(notesLayoutModeProvider));
    final groups = groupReminders(
      notesAsync.value ?? const <Note>[],
      now: DateTime.now(),
    );
    final count = groups.fold(0, (sum, group) => sum + group.$2.length);

    // The notices scroll with the page, so at large text sizes they cannot
    // crowd out what they are about.
    final notices = [
      if (access != null) _AccessNotice(access: access),
      // One notice at a time: the phone's own limits on background apps
      // matter once Android itself lets reminders ring.
      if (access != null && access.notifications && access.exactAlarms)
        const BackgroundHint(),
    ];

    final Widget content;
    if (notesAsync.isLoading && !notesAsync.hasValue) {
      content = _UnderNotices(
        notices: notices,
        scrolls: true,
        child: NotesSkeleton(columns: columns),
      );
    } else if (notesAsync.hasError) {
      content = _UnderNotices(
        notices: notices,
        child: NotesError(
          detail: '${notesAsync.error}',
          onRetry: () => ref.invalidate(reminderNotesProvider),
        ),
      );
    } else if (groups.isEmpty) {
      content = _UnderNotices(notices: notices, child: const _RemindersEmpty());
    } else {
      content = _ReminderSections(
        notices: notices,
        groups: groups,
        columns: columns,
        bottomPadding: Gap.xxl + MediaQuery.paddingOf(context).bottom,
      );
    }

    return ShelfScaffold(
      // Back returns to the grid rather than leaving the app from here.
      canPop: false,
      onBlockedPop: () => context.go('/'),
      drawer: const AppDrawer(currentPath: '/reminders'),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ShelfHeader(
              title: 'Reminders',
              count: notesAsync.hasValue ? count : null,
            ),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}

/// A loading, empty, or error state that fills the page below the notices.
class _UnderNotices extends StatelessWidget {
  const _UnderNotices({
    required this.notices,
    required this.child,
    this.scrolls = false,
  });

  final List<Widget> notices;
  final Widget child;

  /// Whether [child] is itself a scroll view, which takes the space left
  /// rather than measuring its own height.
  final bool scrolls;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: notices,
          ),
        ),
        SliverFillRemaining(hasScrollBody: scrolls, child: child),
      ],
    );
  }
}

class _ReminderSections extends StatelessWidget {
  const _ReminderSections({
    required this.notices,
    required this.groups,
    required this.columns,
    required this.bottomPadding,
  });

  final List<Widget> notices;
  final List<(String, List<Note>)> groups;
  final int columns;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: TimeGutter()),
        CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: notices,
              ),
            ),
            SliverList.builder(
              itemCount: groups.length,
              itemBuilder: (context, index) {
                final (label, notes) = groups[index];
                return Column(
                  key: ValueKey(label),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DayHeader(label: label),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Layout.contentLeft,
                        Gap.xs,
                        Layout.contentRight,
                        Gap.lg,
                      ),
                      child: MasonryColumns(
                        columns: columns,
                        spacing: Layout.cardGap,
                        children: [
                          for (final note in notes)
                            RepaintBoundary(
                              key: ValueKey(note.id),
                              child: NoteTile(
                                key: ValueKey(note.id),
                                note: note,
                                selecting: false,
                                selected: false,
                                onToggleSelected: null,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            SliverToBoxAdapter(child: SizedBox(height: bottomPadding)),
          ],
        ),
      ],
    );
  }
}

/// Says plainly when Android will keep reminders from ringing, or from
/// ringing on time, and offers the one step that fixes it.
class _AccessNotice extends ConsumerWidget {
  const _AccessNotice({required this.access});

  final ReminderAccess access;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colors;
    final scheduler = ref.read(reminderSchedulerProvider);

    final String eyebrow;
    final String body;
    final String action;
    final Future<void> Function() onAction;
    if (!access.notifications) {
      eyebrow = 'NOTIFICATIONS ARE OFF';
      body =
          'Reminders stay on your notes but will not ring until Notes may '
          'send notifications.';
      action = 'Allow notifications';
      onAction = () async {
        if (!await scheduler.requestNotifications()) {
          await scheduler.openNotificationSettings();
        }
        ref.invalidate(reminderAccessProvider);
      };
    } else if (!access.exactAlarms) {
      eyebrow = 'MAY RING LATE';
      body =
          'Android is ringing reminders near their time rather than on it. '
          'Allow exact alarms so they ring on the minute.';
      action = 'Allow exact alarms';
      onAction = () async {
        await scheduler.requestExactAlarms();
        ref.invalidate(reminderAccessProvider);
      };
    } else {
      return const SizedBox.shrink();
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow,
                style: AppText.metaStrong.copyWith(
                  color: access.notifications ? colors.inkMuted : colors.danger,
                ),
              ),
              const SizedBox(height: Gap.xs),
              Text(body, style: AppText.ui.copyWith(color: colors.ink)),
              TextButton(
                onPressed: () => unawaited(onAction()),
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                child: Text(action),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RemindersEmpty extends StatelessWidget {
  const _RemindersEmpty();

  @override
  Widget build(BuildContext context) {
    return const StateMessage(
      eyebrow: 'REMINDERS',
      headline: 'Nothing waiting to ring',
      body:
          'Open a note and tap the alarm to be reminded of it. The reminder '
          'rings even when the app is closed.',
    );
  }
}
