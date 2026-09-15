import 'package:drift/drift.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/db/note_dao.dart';
import 'package:notes/domain/model/note.dart';
import 'package:notes/domain/model/reminder_rule.dart';

/// Setting, changing, and clearing the one reminder a note can carry.
///
/// Only the stored reminder changes here. Notifications follow what is
/// stored: ReminderSync watches it and schedules or cancels to match, so
/// undo, restoring from the trash, and a later import all ring correctly
/// without reaching for the scheduler themselves.
class ReminderRepository {
  ReminderRepository(this._dao);

  final NoteDao _dao;

  /// Notes outside the trash with a reminder, each with the id its
  /// notifications carry.
  Stream<List<(int, Note)>> watchAll() => _dao.watchReminders();

  Future<List<(int, Note)>> loadAll() => _dao.loadReminders();

  Future<Note?> load(String noteId) => _dao.loadNote(noteId);

  /// Sets [noteId] to ring at [at], repeating by [rule] when one is given.
  Future<void> set(String noteId, DateTime at, {ReminderRule? rule}) =>
      _dao.updateNote(
        noteId,
        NotesCompanion(
          reminderAtMs: Value(at.millisecondsSinceEpoch),
          reminderRule: Value(rule),
          reminderDone: const Value(false),
        ),
      );

  /// Changes how the reminder repeats and keeps its time.
  ///
  /// A repeat is never done, so switching to one clears done. Switching back
  /// to a one-off leaves done as it was: a finished reminder stays finished.
  Future<void> setRule(String noteId, ReminderRule? rule) => _dao.updateNote(
    noteId,
    NotesCompanion(
      reminderRule: Value(rule),
      reminderDone: rule == null
          ? const Value.absent()
          : const Value(false),
    ),
  );

  Future<void> clear(String noteId) => _dao.updateNote(
    noteId,
    const NotesCompanion(
      reminderAtMs: Value(null),
      reminderRule: Value(null),
      reminderDone: Value(false),
    ),
  );

  /// Puts back the reminder [previous] had, for undo.
  Future<void> restore(Note previous) => _dao.updateNote(
    previous.id,
    NotesCompanion(
      reminderAtMs: Value(previous.reminderAt?.millisecondsSinceEpoch),
      reminderRule: Value(previous.reminderRule),
      reminderDone: Value(previous.reminderDone),
    ),
  );

  /// Done, from the notification. A one-off reminder is marked done. A
  /// repeating one carries on to its next time: the ring it came from has
  /// already been dismissed.
  Future<void> markDone(String noteId) async {
    final note = await _dao.loadNote(noteId);
    if (note == null || note.reminderAt == null || note.reminderRule != null) {
      return;
    }
    await _dao.updateNote(
      noteId,
      const NotesCompanion(reminderDone: Value(true)),
    );
  }

  /// Snooze, from the notification: a one-off reminder moves to [until].
  ///
  /// Returns false, changing nothing, for a repeating reminder or a note
  /// whose reminder is gone. A repeating reminder keeps its own time, so the
  /// caller rings it once more at [until] instead.
  Future<bool> snooze(String noteId, DateTime until) async {
    final note = await _dao.loadNote(noteId);
    if (note == null || note.reminderAt == null || note.reminderRule != null) {
      return false;
    }
    await set(noteId, until);
    return true;
  }
}
