import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/reminders/reminder_actions.dart';
import 'package:notes/data/repository/note_repository.dart';
import 'package:notes/data/repository/reminder_repository.dart';
import 'package:notes/domain/model/reminder_rule.dart';
import 'package:notes/domain/service/reminder_scheduler.dart';

import '../support/fake_reminder_scheduler.dart';

/// Done and Snooze pressed on a notification, with the app closed.
void main() {
  late AppDatabase db;
  late NoteRepository notes;
  late ReminderRepository reminders;
  late FakeReminderScheduler scheduler;
  late ReminderActions actions;

  final now = DateTime(2026, 9, 16, 8, 0, 30);

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    notes = NoteRepository(db.noteDao);
    reminders = ReminderRepository(db.noteDao);
    scheduler = FakeReminderScheduler();
    actions = ReminderActions(reminders, scheduler, clock: () => now);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> idOf(String noteId) async => (await reminders.loadAll())
      .firstWhere((row) => row.$2.id == noteId)
      .$1;

  test('Done finishes a one-off reminder that has rung', () async {
    final note = await notes.create(title: 'Dentist');
    await reminders.set(note.id, DateTime(2026, 9, 16, 8));

    await actions.handle(ReminderActions.done, note.id);

    final loaded = (await notes.load(note.id))!;
    expect(loaded.reminderDone, isTrue);
    expect(loaded.isReminderOverdue, isFalse);
    expect(scheduler.pending, isEmpty);
  });

  test('Done on a repeating reminder keeps its next ring waiting', () async {
    final note = await notes.create(title: 'Bins out');
    await reminders.set(
      note.id,
      DateTime(2026, 9, 16, 8),
      rule: ReminderRule.weekly,
    );

    await actions.handle(ReminderActions.done, note.id);

    final id = await idOf(note.id);
    expect(scheduler.pending[id]!.at, DateTime(2026, 9, 23, 8));
    expect(scheduler.pending[id]!.repeat, ReminderRule.weekly);
  });

  test('Snooze moves a one-off reminder ten minutes on', () async {
    final note = await notes.create(title: 'Dentist');
    await reminders.set(note.id, DateTime(2026, 9, 16, 8));

    await actions.handle(ReminderActions.snooze, note.id);

    final until = now.add(const Duration(minutes: 10));
    expect((await notes.load(note.id))!.reminderAt, until);
    expect(scheduler.pending[await idOf(note.id)]!.at, until);
  });

  test('Snooze on a repeating reminder rings once more on the side', () async {
    final note = await notes.create(title: 'Bins out');
    await reminders.set(
      note.id,
      DateTime(2026, 9, 16, 8),
      rule: ReminderRule.daily,
    );

    await actions.handle(ReminderActions.snooze, note.id);

    final id = await idOf(note.id);
    final snooze = scheduler.pending[ReminderIds.snoozeOf(id)]!;
    expect(snooze.at, now.add(const Duration(minutes: 10)));
    expect(snooze.repeat, isNull);
    expect(snooze.title, 'Bins out');
    expect((await notes.load(note.id))!.reminderAt, DateTime(2026, 9, 16, 8));
  });

  test('buttons on a notification for a reminder since moved do nothing', () async {
    final note = await notes.create(title: 'Dentist');
    final rang = DateTime(2026, 9, 16, 8);
    await reminders.set(note.id, rang);
    // Moved to tomorrow while the notification was still on screen.
    final moved = DateTime(2026, 9, 17, 8);
    await reminders.set(note.id, moved);

    await actions.handle(ReminderActions.done, note.id, setFor: rang);
    await actions.handle(ReminderActions.snooze, note.id, setFor: rang);

    final loaded = (await notes.load(note.id))!;
    expect(loaded.reminderAt, moved);
    expect(loaded.reminderDone, isFalse);
  });

  test('buttons on the notification of the current reminder still act', () async {
    final note = await notes.create(title: 'Dentist');
    final rang = DateTime(2026, 9, 16, 8);
    await reminders.set(note.id, rang);

    await actions.handle(ReminderActions.done, note.id, setFor: rang);

    expect((await notes.load(note.id))!.reminderDone, isTrue);
  });

  test('swiping away a lone first ring sets up the repeat', () async {
    final note = await notes.create(title: 'Rent');
    // Monthly from this morning's ring, which was scheduled on its own.
    await reminders.set(
      note.id,
      DateTime(2026, 9, 16, 8),
      rule: ReminderRule.monthly,
    );

    await actions.dismissed();

    final ring = scheduler.pending[await idOf(note.id)]!;
    expect(ring.at, DateTime(2026, 10, 16, 8));
    expect(ring.repeat, ReminderRule.monthly);
  });

  test('a notification payload carries the note and its set time', () {
    final setFor = DateTime(2026, 9, 16, 8);
    final payload = ReminderPayload('01a0-note', setFor);

    expect(ReminderPayload.decode(payload.encode()), payload);
    expect(
      ReminderPayload.decode('01a0-note'),
      const ReminderPayload('01a0-note', null),
    );
    expect(ReminderPayload.decode(''), isNull);
  });

  test('an action on a note that has since gone does nothing', () async {
    await actions.handle(ReminderActions.snooze, 'missing');
    await actions.handle(ReminderActions.done, 'missing');

    expect(scheduler.pending, isEmpty);
  });
}
