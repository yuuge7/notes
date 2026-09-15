import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/repository/note_repository.dart';
import 'package:notes/data/repository/reminder_repository.dart';
import 'package:notes/domain/model/reminder_rule.dart';

void main() {
  late AppDatabase db;
  late NoteRepository notes;
  late ReminderRepository reminders;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    notes = NoteRepository(db.noteDao);
    reminders = ReminderRepository(db.noteDao);
  });

  tearDown(() async {
    await db.close();
  });

  final at = DateTime(2026, 9, 16, 8);

  test('sets, changes the repeat, and clears a reminder', () async {
    final note = await notes.create(title: 'Passport');

    await reminders.set(note.id, at, rule: ReminderRule.weekly);
    var loaded = (await notes.load(note.id))!;
    expect(loaded.reminderAt, at);
    expect(loaded.reminderRule, ReminderRule.weekly);

    await reminders.setRule(note.id, null);
    loaded = (await notes.load(note.id))!;
    expect(loaded.reminderAt, at);
    expect(loaded.reminderRule, isNull);

    await reminders.clear(note.id);
    loaded = (await notes.load(note.id))!;
    expect(loaded.hasReminder, isFalse);
  });

  test('a new repeat clears done; going back to once keeps it', () async {
    final note = await notes.create(title: 'Passport');
    await reminders.set(note.id, at);
    await reminders.markDone(note.id);

    await reminders.setRule(note.id, null);
    expect((await notes.load(note.id))!.reminderDone, isTrue);

    await reminders.setRule(note.id, ReminderRule.weekly);
    expect((await notes.load(note.id))!.reminderDone, isFalse);
  });

  test('restore puts back the reminder a note had, for undo', () async {
    final note = await notes.create(title: 'Passport');
    await reminders.set(note.id, at, rule: ReminderRule.monthly);
    final before = (await notes.load(note.id))!;

    await reminders.clear(note.id);
    await reminders.restore(before);

    final after = (await notes.load(note.id))!;
    expect(after.reminderAt, at);
    expect(after.reminderRule, ReminderRule.monthly);
  });

  test('done marks a one-off reminder and leaves a repeating one', () async {
    final once = await notes.create(title: 'Once');
    final weekly = await notes.create(title: 'Weekly');
    await reminders.set(once.id, at);
    await reminders.set(weekly.id, at, rule: ReminderRule.weekly);

    await reminders.markDone(once.id);
    await reminders.markDone(weekly.id);

    expect((await notes.load(once.id))!.reminderDone, isTrue);
    expect((await notes.load(weekly.id))!.reminderDone, isFalse);
  });

  test('setting a new time clears done', () async {
    final note = await notes.create(title: 'Once');
    await reminders.set(note.id, at);
    await reminders.markDone(note.id);

    await reminders.set(note.id, at.add(const Duration(days: 1)));

    expect((await notes.load(note.id))!.reminderDone, isFalse);
  });

  test('snooze moves a one-off reminder, not a repeating one', () async {
    final once = await notes.create(title: 'Once');
    final daily = await notes.create(title: 'Daily');
    await reminders.set(once.id, at);
    await reminders.set(daily.id, at, rule: ReminderRule.daily);
    final until = at.add(const Duration(minutes: 10));

    expect(await reminders.snooze(once.id, until), isTrue);
    expect(await reminders.snooze(daily.id, until), isFalse);

    expect((await notes.load(once.id))!.reminderAt, until);
    expect((await notes.load(daily.id))!.reminderAt, at);
  });

  test('lists reminders soonest first, archived included, trash left out', () async {
    final later = await notes.create(title: 'Later');
    final sooner = await notes.create(title: 'Sooner');
    final archived = await notes.create(title: 'Archived');
    final trashed = await notes.create(title: 'Trashed');
    await notes.create(title: 'No reminder');
    await reminders.set(later.id, at.add(const Duration(days: 2)));
    await reminders.set(sooner.id, at);
    await reminders.set(archived.id, at.add(const Duration(days: 1)));
    await reminders.set(trashed.id, at);
    await notes.setArchived(archived.id, archived: true);
    await notes.delete(trashed.id);

    final rows = await reminders.loadAll();

    expect([for (final (_, note) in rows) note.title], [
      'Sooner',
      'Archived',
      'Later',
    ]);
    // Each note keeps its notification id from one read to the next.
    final ids = {for (final (id, note) in rows) note.id: id};
    expect(ids.values.toSet(), hasLength(3));
    await notes.saveText(sooner.id, title: 'Sooner, edited');
    expect(
      {for (final (id, note) in await reminders.loadAll()) note.id: id},
      ids,
    );
  });
}
