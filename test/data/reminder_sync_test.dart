import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/reminders/reminder_sync.dart';
import 'package:notes/data/repository/checklist_repository.dart';
import 'package:notes/data/repository/note_repository.dart';
import 'package:notes/data/repository/reminder_repository.dart';
import 'package:notes/domain/model/note_type.dart';
import 'package:notes/domain/model/reminder_rule.dart';
import 'package:notes/domain/service/reminder_scheduler.dart';

import '../support/fake_reminder_scheduler.dart';

/// Stored reminders and scheduled notifications agree, whatever path changed
/// the note.
void main() {
  late AppDatabase db;
  late NoteRepository notes;
  late ReminderRepository reminders;
  late FakeReminderScheduler scheduler;
  late ReminderSync sync;

  // 15 September 2026, a Tuesday.
  var now = DateTime(2026, 9, 15, 10);

  setUp(() {
    now = DateTime(2026, 9, 15, 10);
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    notes = NoteRepository(db.noteDao);
    reminders = ReminderRepository(db.noteDao);
    scheduler = FakeReminderScheduler();
    sync = ReminderSync(reminders, scheduler, clock: () => now);
  });

  tearDown(() async {
    await sync.dispose();
    await db.close();
  });

  /// Lets the watch deliver the latest write and the sync act on it.
  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await sync.idle;
    }
  }

  Future<int> idOf(String noteId) async => (await reminders.loadAll())
      .firstWhere((row) => row.$2.id == noteId)
      .$1;

  test('a reminder set on a note is scheduled with the note text', () async {
    sync.start();
    final note = await notes.create(
      title: 'Renew passport',
      body: 'Bring the old one.\n\nAnd a photo.',
    );
    await reminders.set(note.id, DateTime(2026, 9, 16, 8));
    await settle();

    final id = await idOf(note.id);
    expect(
      scheduler.pending[id],
      ScheduledReminder(
        id: id,
        noteId: note.id,
        title: 'Renew passport',
        body: 'Bring the old one.\nAnd a photo.',
        at: DateTime(2026, 9, 16, 8),
        setFor: DateTime(2026, 9, 16, 8),
        exact: true,
      ),
    );
  });

  test('a list without a title rings with its first open item', () async {
    sync.start();
    final note = await notes.create(type: NoteType.checklist);
    final lists = ChecklistRepository(db.noteDao);
    await lists.add(note.id, text: 'Oat milk');
    await lists.add(note.id, text: 'Eggs');
    await reminders.set(note.id, DateTime(2026, 9, 16, 8));
    await settle();

    final reminder = scheduler.pending[await idOf(note.id)]!;
    expect(reminder.title, '☐ Oat milk');
    expect(reminder.body, '☐ Eggs');
  });

  test('editing the title reschedules; an unrelated write does not', () async {
    sync.start();
    final note = await notes.create(title: 'Dentist');
    final other = await notes.create(title: 'Other');
    await reminders.set(note.id, DateTime(2026, 9, 16, 8));
    await settle();
    final id = await idOf(note.id);
    scheduler.log.clear();

    await notes.saveText(other.id, title: 'Other, edited');
    await settle();
    expect(scheduler.log, isEmpty);

    await notes.saveText(note.id, title: 'Dentist, Dr. Pop');
    await settle();
    expect(scheduler.log, ['schedule $id']);
    expect(scheduler.pending[id]!.title, 'Dentist, Dr. Pop');
  });

  test('trash cancels, restore schedules again, archive keeps it', () async {
    sync.start();
    final note = await notes.create(title: 'Dentist');
    await reminders.set(note.id, DateTime(2026, 9, 16, 8));
    await settle();
    final id = await idOf(note.id);

    await notes.setArchived(note.id, archived: true);
    await settle();
    expect(scheduler.pending, contains(id));

    await notes.delete(note.id);
    await settle();
    expect(scheduler.pending, isNot(contains(id)));

    await notes.restore(note.id);
    await settle();
    expect(scheduler.pending, contains(id));
  });

  test('clearing a reminder cancels it and any snooze of it', () async {
    sync.start();
    final note = await notes.create(title: 'Dentist');
    await reminders.set(note.id, DateTime(2026, 9, 16, 8));
    await settle();
    final id = await idOf(note.id);

    await reminders.clear(note.id);
    await settle();

    expect(scheduler.pending, isEmpty);
    expect(
      scheduler.log,
      containsAllInOrder(['cancel $id', 'cancel ${ReminderIds.snoozeOf(id)}']),
    );
  });

  test('a repeat turned into a one-off that has passed stops ringing', () async {
    sync.start();
    final note = await notes.create(title: 'Bins out');
    await reminders.set(
      note.id,
      DateTime(2026, 9, 14, 7),
      rule: ReminderRule.daily,
    );
    await settle();
    final id = await idOf(note.id);
    expect(scheduler.pending[id]!.repeat, ReminderRule.daily);

    await reminders.setRule(note.id, null);
    await settle();

    expect(scheduler.pending, isNot(contains(id)));
    expect(scheduler.log, contains('cancel ${ReminderIds.snoozeOf(id)}'));
  });

  test('a reminder that has rung stays on screen through later writes', () async {
    sync.start();
    final note = await notes.create(title: 'Dentist');
    await reminders.set(note.id, DateTime(2026, 9, 15, 11));
    await settle();
    final id = await idOf(note.id);

    now = DateTime(2026, 9, 15, 11, 1);
    await notes.saveText(note.id, body: 'Entrance from the courtyard.');
    await settle();

    expect(scheduler.log, isNot(contains('cancel $id')));
  });

  test('done cancels the notification of a one-off reminder', () async {
    sync.start();
    final note = await notes.create(title: 'Dentist');
    await reminders.set(note.id, DateTime(2026, 9, 16, 8));
    await settle();
    final id = await idOf(note.id);

    await reminders.markDone(note.id);
    await settle();

    expect(scheduler.pending, isNot(contains(id)));
  });

  test('a repeating reminder is scheduled for its next ring', () async {
    sync.start();
    final note = await notes.create(title: 'Bins out');
    // Monday 14 September at 07:00, weekly.
    await reminders.set(
      note.id,
      DateTime(2026, 9, 14, 7),
      rule: ReminderRule.weekly,
    );
    await settle();

    final reminder = scheduler.pending[await idOf(note.id)]!;
    expect(reminder.at, DateTime(2026, 9, 21, 7));
    expect(reminder.repeat, ReminderRule.weekly);
  });

  test('a far-off first ring is scheduled alone, then repeats', () async {
    sync.start();
    final note = await notes.create(title: 'Rent');
    await reminders.set(
      note.id,
      DateTime(2026, 11, 15, 9),
      rule: ReminderRule.monthly,
    );
    await settle();
    final id = await idOf(note.id);

    expect(scheduler.pending[id]!.at, DateTime(2026, 11, 15, 9));
    expect(scheduler.pending[id]!.repeat, isNull);

    now = DateTime(2026, 11, 15, 9, 5);
    await sync.refresh();

    expect(scheduler.pending[id]!.at, DateTime(2026, 12, 15, 9));
    expect(scheduler.pending[id]!.repeat, ReminderRule.monthly);
  });

  test('losing exact alarms reschedules every reminder as inexact', () async {
    sync.start();
    final note = await notes.create(title: 'Dentist');
    await reminders.set(note.id, DateTime(2026, 9, 16, 8));
    await settle();
    final id = await idOf(note.id);

    scheduler.currentAccess = const ReminderAccess(
      notifications: true,
      exactAlarms: false,
    );
    await sync.refresh();

    expect(scheduler.pending[id]!.exact, isFalse);
  });

  test('the first pass cancels leftovers but not snoozes', () async {
    final note = await notes.create(title: 'Dentist');
    await reminders.set(note.id, DateTime(2026, 9, 16, 8));
    final id = await idOf(note.id);
    ScheduledReminder stray(int strayId) => ScheduledReminder(
      id: strayId,
      noteId: 'gone',
      title: 'Gone',
      body: '',
      at: DateTime(2026, 9, 20),
      setFor: DateTime(2026, 9, 20),
      exact: true,
    );
    scheduler.pending
      ..[id + 100] = stray(id + 100)
      ..[ReminderIds.snoozeOf(id)] = stray(ReminderIds.snoozeOf(id));

    sync.start();
    await settle();

    expect(scheduler.pending.keys, unorderedEquals([id, ReminderIds.snoozeOf(id)]));
  });
}
