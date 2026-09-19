import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/repository/label_repository.dart';
import 'package:notes/data/repository/note_repository.dart';

void main() {
  late AppDatabase db;
  late NoteRepository notes;
  late LabelRepository labels;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    notes = NoteRepository(db.noteDao);
    labels = LabelRepository(db.noteDao);
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<String>> labelNames() async => [
    for (final label in await labels.all()) label.name,
  ];

  Future<List<String>> labelsOn(String noteId) async => [
    for (final label in (await notes.load(noteId))!.labels) label.name,
  ];

  test('a deleted label goes on no note', () async {
    final note = await notes.create(title: 'Boiler');
    final gone = await labels.create('Gone');
    await labels.delete(gone.id);

    await labels.setOnNotes([note.id], gone.id, on: true);

    expect(await labelsOn(note.id), isEmpty);
    // Brought back, it is on none of the notes it was never put on.
    await labels.restore((labelId: gone.id, noteIds: const []));
    expect(await labelsOn(note.id), isEmpty);
  });

  group('create', () {
    test('lists labels in the order they were made', () async {
      await labels.create('Home');
      await labels.create('Admin');

      expect(await labelNames(), ['Home', 'Admin']);
    });

    test('a name that exists in another case is the same label', () async {
      final home = await labels.create('Home');
      final again = await labels.create('  home ');

      expect(again.id, home.id);
      expect(await labelNames(), ['Home']);
    });

    test('tidies spaces and caps the length', () async {
      expect((await labels.create('  Long   weekend  ')).name, 'Long weekend');
      expect(
        (await labels.create('x' * 80)).name,
        hasLength(LabelRepository.maxLength),
      );
    });

    test('refuses a blank name', () {
      expect(() => labels.create('   '), throwsArgumentError);
    });
  });

  group('rename', () {
    test('renames a label', () async {
      final home = await labels.create('Home');

      expect(await labels.rename(home.id, 'House'), RenameResult.renamed);
      expect(await labelNames(), ['House']);
    });

    test('may change only the case', () async {
      final home = await labels.create('home');

      expect(await labels.rename(home.id, 'Home'), RenameResult.renamed);
      expect(await labelNames(), ['Home']);
    });

    test('refuses a name another label has, ignoring case', () async {
      await labels.create('Home');
      final admin = await labels.create('Admin');

      expect(await labels.rename(admin.id, 'HOME'), RenameResult.taken);
      expect(await labelNames(), ['Home', 'Admin']);
    });

    test('refuses a blank name', () async {
      final home = await labels.create('Home');

      expect(await labels.rename(home.id, '  '), RenameResult.empty);
      expect(await labelNames(), ['Home']);
    });
  });

  group('delete', () {
    test('takes the label off its notes and keeps the notes', () async {
      final note = await notes.create(title: 'Boiler');
      final home = await labels.create('Home');
      await labels.setOnNotes([note.id], home.id, on: true);

      final deleted = await labels.delete(home.id);

      expect(await labelNames(), isEmpty);
      expect(await labelsOn(note.id), isEmpty);
      expect(deleted.noteIds, [note.id]);
      expect(await notes.count(), 1);
    });

    test('frees the name for a new label', () async {
      final home = await labels.create('Home');
      await labels.delete(home.id);

      final again = await labels.create('Home');

      expect(again.id, isNot(home.id));
      expect(await labelNames(), ['Home']);
    });

    test('undo puts the label back on the same notes', () async {
      final note = await notes.create(title: 'Boiler');
      final home = await labels.create('Home');
      await labels.setOnNotes([note.id], home.id, on: true);

      await labels.restore(await labels.delete(home.id));

      expect(await labelNames(), ['Home']);
      expect(await labelsOn(note.id), ['Home']);
    });

    test('undo after the name was reused joins the new label', () async {
      final note = await notes.create(title: 'Boiler');
      final home = await labels.create('Home');
      await labels.setOnNotes([note.id], home.id, on: true);
      final deleted = await labels.delete(home.id);
      await labels.create('home');

      await labels.restore(deleted);

      expect(await labelNames(), ['home']);
      expect(await labelsOn(note.id), ['home']);
    });
  });

  test('reorder places a label between two others', () async {
    final a = await labels.create('A');
    final b = await labels.create('B');
    final c = await labels.create('C');

    await labels.reorder(c.id, prevKey: a.sortKey, nextKey: b.sortKey);

    expect(await labelNames(), ['A', 'C', 'B']);
  });

  group('on notes', () {
    test('goes on several notes at once and comes off again', () async {
      final a = await notes.create(title: 'A');
      final b = await notes.create(title: 'B');
      final home = await labels.create('Home');

      await labels.setOnNotes([a.id, b.id], home.id, on: true);
      expect(await labelsOn(a.id), ['Home']);
      expect(await labelsOn(b.id), ['Home']);

      await labels.setOnNotes([a.id, b.id], home.id, on: false);
      expect(await labelsOn(a.id), isEmpty);
      expect(await labelsOn(b.id), isEmpty);
    });

    test('taken off and put back on, a label is on the note once', () async {
      final note = await notes.create(title: 'A');
      final home = await labels.create('Home');

      await labels.setOnNotes([note.id], home.id, on: true);
      await labels.setOnNotes([note.id], home.id, on: false);
      await labels.setOnNotes([note.id], home.id, on: true);

      expect(await labelsOn(note.id), ['Home']);
    });

    test('a label shows the notes on the grid that wear it', () async {
      final kept = await notes.create(title: 'Kept');
      final archived = await notes.create(title: 'Archived');
      await notes.create(title: 'Unlabelled');
      final home = await labels.create('Home');
      await labels.setOnNotes([kept.id, archived.id], home.id, on: true);
      await notes.setArchived(archived.id, archived: true);

      final shown = await labels.watchNotes(home.id).first;

      expect([for (final note in shown) note.title], ['Kept']);
    });

    test('usage counts how many of the given notes wear each label', () async {
      final a = await notes.create(title: 'A');
      final b = await notes.create(title: 'B');
      final home = await labels.create('Home');
      final admin = await labels.create('Admin');
      await labels.setOnNotes([a.id, b.id], home.id, on: true);
      await labels.setOnNotes([a.id], admin.id, on: true);

      expect(await labels.watchUsage([a.id, b.id]).first, {
        home.id: 2,
        admin.id: 1,
      });
    });
  });
}
