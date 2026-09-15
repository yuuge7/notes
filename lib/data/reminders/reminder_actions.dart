import 'package:notes/core/util/reminder_time.dart';
import 'package:notes/data/reminders/reminder_sync.dart';
import 'package:notes/data/repository/reminder_repository.dart';
import 'package:notes/domain/service/reminder_scheduler.dart';

/// What Done, Snooze, and swiping away do to a reminder notification.
///
/// These run where the notification was handled, often with the app closed,
/// so each one also brings the scheduled notifications in line itself rather
/// than waiting for the app to notice.
class ReminderActions {
  ReminderActions(this._reminders, this._scheduler, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const done = 'done';
  static const snooze = 'snooze';

  final ReminderRepository _reminders;
  final ReminderScheduler _scheduler;
  final DateTime Function() _clock;

  /// Runs the button with [actionId] for [noteId]. Unknown buttons do
  /// nothing.
  ///
  /// [setFor] is the reminder time the notification was scheduled with. When
  /// the note's reminder has been moved or removed since, the buttons leave
  /// the note alone: Done on an old notification must not finish tomorrow's
  /// reminder.
  Future<void> handle(
    String? actionId,
    String noteId, {
    DateTime? setFor,
  }) async {
    if (setFor != null) {
      final note = await _reminders.load(noteId);
      if (note == null || note.reminderAt != setFor) return;
    }
    switch (actionId) {
      case done:
        await markDone(noteId);
      case snooze:
        await snoozeNote(noteId);
    }
  }

  /// A notification swiped away. A repeating reminder whose first ring was
  /// scheduled on its own gets its repeat set up here, without waiting for
  /// the app to be opened.
  Future<void> dismissed() => _syncOnce();

  /// A one-off reminder is finished; a repeating one waits for its next
  /// ring.
  Future<void> markDone(String noteId) async {
    await _reminders.markDone(noteId);
    await _syncOnce();
  }

  /// Rings again in ten minutes. A one-off reminder moves; a repeating one
  /// keeps its schedule and rings once more on the side.
  Future<void> snoozeNote(String noteId) async {
    final now = _clock();
    final until = now.add(ReminderTime.snooze);
    if (await _reminders.snooze(noteId, until)) {
      await _syncOnce();
      return;
    }

    final rows = await _reminders.loadAll();
    for (final (id, note) in rows) {
      if (note.id != noteId) continue;
      final access = await _scheduler.access();
      final ring = ReminderSync.wantedFor(
        id,
        note,
        now: now,
        exact: access.exactAlarms,
      );
      if (ring == null) return;
      await _scheduler.schedule(
        ScheduledReminder(
          id: ReminderIds.snoozeOf(id),
          noteId: noteId,
          title: ring.title,
          body: ring.body,
          at: until,
          setFor: ring.setFor,
          exact: ring.exact,
        ),
      );
    }
  }

  Future<void> _syncOnce() async {
    final sync = ReminderSync(_reminders, _scheduler, clock: _clock);
    await sync.refresh();
  }
}
