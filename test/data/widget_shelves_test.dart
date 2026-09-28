import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/repository/label_repository.dart';
import 'package:notes/data/repository/note_repository.dart';
import 'package:notes/domain/model/note_page.dart';

/// The notes each home screen widget can show: the grid, the pinned notes,
/// and every label's page, read together.
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

  tearDown(() => db.close());

  List<String> titles(NotePage page) => [
    for (final note in page.notes) note.title,
  ];

  test('each shelf in grid order, counted in full', () async {
    final home = await labels.create('Home');
    final admin = await labels.create('Admin');
    // Created last, each lands on top of the grid.
    final boiler = await notes.create(title: 'Boiler');
    final tiles = await notes.create(title: 'Tiles');
    final passport = await notes.create(title: 'Passport');
    await notes.create(title: 'Bike');
    await notes.setPinned(tiles.id, pinned: true);
    await labels.setOnNotes([boiler.id, tiles.id], home.id, on: true);
    await labels.setOnNotes([passport.id], admin.id, on: true);

    final shelves = await db.noteDao.loadWidgetShelves(2);

    expect(titles(shelves.all), ['Tiles', 'Bike']);
    expect(shelves.all.total, 4);
    expect(titles(shelves.pinned), ['Tiles']);
    expect(shelves.pinned.total, 1);
    expect(
      [for (final shelf in shelves.labels) shelf.label.name],
      ['Home', 'Admin'],
    );
    expect(titles(shelves.labels[0].page), ['Tiles', 'Boiler']);
    expect(shelves.labels[0].page.total, 2);
    expect(titles(shelves.labels[1].page), ['Passport']);
    expect(shelves.labels[1].page.total, 1);
  });

  test('a note on several shelves comes whole on each', () async {
    final home = await labels.create('Home');
    final tiles = await notes.create(title: 'Tiles');
    await notes.setPinned(tiles.id, pinned: true);
    await labels.setOnNotes([tiles.id], home.id, on: true);

    final shelves = await db.noteDao.loadWidgetShelves(20);

    for (final page in [
      shelves.all,
      shelves.pinned,
      shelves.labels.single.page,
    ]) {
      expect(page.notes.single.labels.single.name, 'Home');
      expect(page.notes.single.pinned, isTrue);
    }
  });

  test(
    'archived and trashed notes, and deleted labels, are left out',
    () async {
      final home = await labels.create('Home');
      final gone = await labels.create('Gone');
      final archived = await notes.create(title: 'Archived');
      final trashed = await notes.create(title: 'Trashed');
      final kept = await notes.create(title: 'Kept');
      for (final note in [archived, trashed, kept]) {
        await notes.setPinned(note.id, pinned: true);
      }
      await labels.setOnNotes(
        [archived.id, trashed.id, kept.id],
        home.id,
        on: true,
      );
      await notes.setArchived(archived.id, archived: true);
      await notes.delete(trashed.id);
      await labels.delete(gone.id);

      final shelves = await db.noteDao.loadWidgetShelves(20);

      expect(titles(shelves.all), ['Kept']);
      expect(titles(shelves.pinned), ['Kept']);
      expect(shelves.pinned.total, 1);
      expect(shelves.labels.single.label.name, 'Home');
      expect(titles(shelves.labels.single.page), ['Kept']);
      expect(shelves.labels.single.page.total, 1);
    },
  );

  test('a label on no notes is still a shelf, empty', () async {
    await labels.create('Someday');

    final shelves = await db.noteDao.loadWidgetShelves(20);

    expect(shelves.labels.single.label.name, 'Someday');
    expect(shelves.labels.single.page.notes, isEmpty);
    expect(shelves.labels.single.page.total, 0);
  });

  test('offers the grid past the shelves, for a note widget', () async {
    for (final title in ['Boiler', 'Tiles', 'Passport', 'Bike']) {
      await notes.create(title: title);
    }

    final shelves = await db.noteDao.loadWidgetShelves(2, choices: 3);

    expect(titles(shelves.all), ['Bike', 'Passport']);
    expect(
      [for (final note in shelves.choices) note.title],
      ['Bike', 'Passport', 'Tiles'],
    );
  });

  test('carries the notes on note widgets, wherever they are', () async {
    final list = await notes.create(title: 'Groceries');
    final archived = await notes.create(title: 'Winter tyres');
    final trashed = await notes.create(title: 'Old lease');
    for (var i = 0; i < 3; i++) {
      await notes.create(title: 'Newer $i');
    }
    await notes.setArchived(archived.id, archived: true);
    await notes.delete(trashed.id);

    final shelves = await db.noteDao.loadWidgetShelves(
      2,
      pages: {list.id, archived.id, trashed.id, 'never-was'},
    );

    expect(titles(shelves.all), isNot(contains('Groceries')));
    expect(shelves.pages[list.id]?.title, 'Groceries');
    // Archived, a note still shows on its widget; in the trash it is gone.
    expect(shelves.pages[archived.id]?.title, 'Winter tyres');
    expect(shelves.pages.keys, hasLength(4));
    expect(shelves.pages[trashed.id], isNull);
    expect(shelves.pages['never-was'], isNull);
  });

  test('reloads when a label changes, not only a note', () async {
    final home = await labels.create('Home');
    final seen = <List<String>>[];
    final watching = notes
        .watchWidgetShelves(20)
        .listen(
          (shelves) =>
              seen.add([for (final shelf in shelves.labels) shelf.label.name]),
        );
    await pumpEventQueue();

    await labels.rename(home.id, 'House');
    await pumpEventQueue();
    await watching.cancel();

    expect(seen.first, ['Home']);
    expect(seen.last, ['House']);
  });
}
