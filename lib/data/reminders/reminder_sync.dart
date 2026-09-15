import 'dart:async';

import 'package:notes/core/util/reminder_time.dart';
import 'package:notes/data/repository/reminder_repository.dart';
import 'package:notes/domain/model/note.dart';
import 'package:notes/domain/model/reminder_rule.dart';
import 'package:notes/domain/service/reminder_scheduler.dart';

/// Keeps the system's scheduled notifications in line with the reminders
/// stored on notes.
///
/// Nothing that changes a note calls the scheduler. This watches the stored
/// reminders and schedules, replaces, or cancels until the alarms match, so
/// every path that writes a note rings correctly: editing, undo, the trash
/// and restoring from it, and imports still to come.
class ReminderSync {
  ReminderSync(this._reminders, this._scheduler, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// Longest notification text, in characters. Android folds the rest away
  /// in any case.
  static const _bodyLimit = 280;

  final ReminderRepository _reminders;
  final ReminderScheduler _scheduler;
  final DateTime Function() _clock;

  /// What this sync has handed to the scheduler, by notification id.
  final _scheduled = <int, ScheduledReminder>{};
  StreamSubscription<List<(int, Note)>>? _subscription;
  Future<void> _queue = Future.value();

  /// Whether the next pass should first compare against what the system has
  /// waiting, which may be left over from an earlier run of the app.
  bool _fresh = true;

  /// Starts following the stored reminders. The first pass also cancels
  /// notifications left waiting for reminders that no longer exist.
  void start() {
    _subscription ??= _reminders.watchAll().listen(
      (rows) => unawaited(_enqueue(() => _apply(rows))),
    );
  }

  /// Checks again without a change to the notes, as when the app returns
  /// from settings with a permission granted or taken away.
  Future<void> refresh() =>
      _enqueue(() async => _apply(await _reminders.loadAll()));

  /// Resolves once every pass queued so far has finished.
  Future<void> get idle => _queue;

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _enqueue(Future<void> Function() pass) => _queue = _queue
      .then((_) => pass())
      .catchError(
        // A failed pass must not stall the ones behind it.
        (Object error, StackTrace stack) =>
            Zone.current.handleUncaughtError(error, stack),
      );

  Future<void> _apply(List<(int, Note)> rows) async {
    final now = _clock();
    final access = await _scheduler.access();

    final wanted = <int, ScheduledReminder>{};
    // One-off reminders whose time has come, with the time each was set for.
    // Their notification may be on screen right now, and cancelling would
    // take it away.
    final rung = <int, DateTime>{};
    for (final (id, note) in rows) {
      final reminder = wantedFor(id, note, now: now, exact: access.exactAlarms);
      if (reminder != null) {
        wanted[id] = reminder;
      } else if (_hasRung(note, now)) {
        rung[id] = note.reminderAt!;
      }
    }

    if (_fresh) {
      _fresh = false;
      _scheduled.clear();
      for (final id in await _scheduler.pendingIds()) {
        final keep =
            wanted.containsKey(id) ||
            rung.containsKey(id) ||
            // A snooze rings once and clears itself.
            ReminderIds.isSnooze(id);
        if (!keep) await _scheduler.cancel(id);
      }
    }

    for (final MapEntry(key: id, value: reminder) in wanted.entries) {
      if (_scheduled[id] == reminder) continue;
      await _scheduler.schedule(reminder);
      _scheduled[id] = reminder;
    }

    for (final id in [..._scheduled.keys]) {
      if (wanted.containsKey(id)) continue;
      final previous = _scheduled.remove(id)!;
      // The one-off that was waiting has just rung: its notification stays.
      // Anything else waiting under this id, such as a repeat just turned
      // into a one-off whose time has passed, would go on ringing.
      if (previous.repeat == null && rung[id] == previous.setFor) continue;
      await _scheduler.cancel(id);
      await _scheduler.cancel(ReminderIds.snoozeOf(id));
    }
  }

  /// The notification [note] should have waiting under [id] at [now], or
  /// null when nothing should be waiting.
  static ScheduledReminder? wantedFor(
    int id,
    Note note, {
    required DateTime now,
    required bool exact,
  }) {
    final at = note.reminderAt;
    if (at == null || note.deleted) return null;
    final rule = note.reminderRule;

    if (rule == null) {
      if (note.reminderDone || !at.isAfter(now)) return null;
      return _reminder(id, note, at: at, exact: exact);
    }

    final next = ReminderTime.next(at, rule, now);
    // Android places a repeat from today, so a first ring more than one
    // repeat away would come early. It is scheduled on its own instead, and
    // the repeat is set up on the first pass after it has rung.
    final repeatsOnTime = ReminderTime.repeatsFrom(next, rule, now) == next;
    return _reminder(
      id,
      note,
      at: next,
      repeat: repeatsOnTime ? rule : null,
      exact: exact,
    );
  }

  static bool _hasRung(Note note, DateTime now) =>
      note.reminderAt != null &&
      note.reminderRule == null &&
      !note.reminderDone &&
      !note.reminderAt!.isAfter(now);

  static ScheduledReminder _reminder(
    int id,
    Note note, {
    required DateTime at,
    required bool exact,
    ReminderRule? repeat,
  }) {
    final lines = _lines(note);
    final title = note.title.trim();
    final heading = title.isNotEmpty
        ? title
        : lines.isNotEmpty
        ? lines.removeAt(0)
        : 'Reminder';
    final body = lines.join('\n');
    return ScheduledReminder(
      id: id,
      noteId: note.id,
      title: heading,
      body: body.length > _bodyLimit
          ? '${body.substring(0, _bodyLimit).trimRight()}…'
          : body,
      at: at,
      setFor: note.reminderAt!,
      repeat: repeat,
      exact: exact,
    );
  }

  /// The note's text as lines worth reading: a text note's non-blank lines,
  /// or a list's open items.
  static List<String> _lines(Note note) => note.isChecklist
      ? [
          for (final item in note.uncheckedItems)
            if (item.text.trim().isNotEmpty) '☐ ${item.text.trim()}',
        ]
      : [
          for (final line in note.body.split('\n'))
            if (line.trim().isNotEmpty) line.trim(),
        ];
}
