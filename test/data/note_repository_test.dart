import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/db/note_dao.dart';
import 'package:notes/data/repository/note_repository.dart';
import 'package:notes/data/seed.dart';
import 'package:notes/domain/model/pigment.dart';

void main() {
  late AppDatabase db;
  late NoteRepository repository;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    repository = NoteRepository(db.noteDao);
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<String>> titles(Shelf shelf) async =>
      (await db.noteDao.loadShelf(shelf)).map((note) => note.title).toList();

  group('create', () {
    test('a new note lands above every existing note', () async {
      await repository.create(title: 'First');
      await repository.create(title: 'Second');
      await repository.create(title: 'Third');

      expect(await titles(Shelf.active), ['Third', 'Second', 'First']);
    });

    test('stores text and pigment as given', () async {
      final note = await repository.create(
        title: 'Bike',
        body: 'Rear brake pads',
        pigment: Pigment.moss,
      );

      expect(note.title, 'Bike');
      expect(note.body, 'Rear brake pads');
      expect(note.pigment, Pigment.moss);
      expect(note.pinned, isFalse);
    });
  });

  group('shelves', () {
    test('pinned notes float above newer unpinned notes', () async {
      final old = await repository.create(title: 'Old');
      await repository.create(title: 'New');

      await repository.setPinned(old.id, pinned: true);

      expect(await titles(Shelf.active), ['Old', 'New']);
    });

    test('archiving moves a note off the grid and onto the archive', () async {
      final note = await repository.create(title: 'Receipt');

      await repository.setArchived(note.id, archived: true);

      expect(await titles(Shelf.active), isEmpty);
      expect(await titles(Shelf.archived), ['Receipt']);
    });

    test('delete sends a note to the trash and restore brings it back', () async {
      final note = await repository.create(title: 'Draft');

      await repository.delete(note.id);
      expect(await titles(Shelf.active), isEmpty);
      expect(await titles(Shelf.trash), ['Draft']);
      expect((await repository.load(note.id))!.deletedAt, isNotNull);

      await repository.restore(note.id);
      expect(await titles(Shelf.active), ['Draft']);
      expect(await titles(Shelf.trash), isEmpty);
      expect((await repository.load(note.id))!.deletedAt, isNull);
    });
  });

  group('trash retention', () {
    test('purge keeps notes trashed within the retention window', () async {
      final note = await repository.create(title: 'Recent');
      await repository.delete(note.id);

      final removed = await repository.purgeExpiredTrash(
        const Duration(days: 7),
      );

      expect(removed, 0);
      expect(await titles(Shelf.trash), ['Recent']);
    });

    test('purge follows the retention it is given', () async {
      final older = await repository.create(title: 'Ten days');
      final newer = await repository.create(title: 'Two days');
      Future<void> trashDaysAgo(String id, int days) async {
        await repository.delete(id);
        await db.noteDao.updateNote(
          id,
          NotesCompanion(
            deletedAtMs: Value(
              DateTime.now()
                  .subtract(Duration(days: days))
                  .millisecondsSinceEpoch,
            ),
          ),
        );
      }

      await trashDaysAgo(older.id, 10);
      await trashDaysAgo(newer.id, 2);

      expect(await repository.purgeExpiredTrash(const Duration(days: 30)), 0);
      expect(await repository.purgeExpiredTrash(const Duration(days: 7)), 1);
      expect(await titles(Shelf.trash), ['Two days']);
      expect(await repository.purgeExpiredTrash(const Duration(days: 1)), 1);
      expect(await titles(Shelf.trash), isEmpty);
    });

    test('purge removes notes trashed before the cutoff', () async {
      final note = await repository.create(title: 'Old');
      await repository.delete(note.id);

      final removed = await db.noteDao.purgeTrashedBefore(
        DateTime.now().add(const Duration(minutes: 1)),
      );

      expect(removed, 1);
      expect(await repository.load(note.id), isNull);
    });

    test('purge never touches notes that are not in the trash', () async {
      await repository.create(title: 'Live');

      final removed = await db.noteDao.purgeTrashedBefore(
        DateTime.now().add(const Duration(days: 365)),
      );

      expect(removed, 0);
      expect(await titles(Shelf.active), ['Live']);
    });
  });

  group('editing', () {
    test('saveText updates only the fields passed', () async {
      final note = await repository.create(title: 'Title', body: 'Body');

      await repository.saveText(note.id, body: 'New body');

      final saved = (await repository.load(note.id))!;
      expect(saved.title, 'Title');
      expect(saved.body, 'New body');
    });

    test('edits stamp updatedAt without moving the note', () async {
      final first = await repository.create(title: 'First');
      await repository.create(title: 'Second');

      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repository.saveText(first.id, title: 'First, edited');

      final saved = (await repository.load(first.id))!;
      expect(saved.updatedAt.isAfter(first.updatedAt), isTrue);
      expect(await titles(Shelf.active), ['Second', 'First, edited']);
    });

    test('checking an item writes through to the note', () async {
      await seedIfEmpty(db.noteDao);
      final groceries = (await db.noteDao.loadShelf(
        Shelf.active,
      )).firstWhere((note) => note.title == 'Groceries');
      final milk = groceries.items.firstWhere((i) => i.text == 'Oat milk');

      await repository.setItemChecked(groceries.id, milk.id, checked: true);

      final saved = (await repository.load(groceries.id))!;
      expect(saved.items.firstWhere((i) => i.id == milk.id).checked, isTrue);
      expect(saved.checkedItems, hasLength(3));
    });

    test('reorder places a note between two neighbours', () async {
      final a = await repository.create(title: 'A');
      final b = await repository.create(title: 'B');
      final c = await repository.create(title: 'C');
      // Grid order is C, B, A. Move A between C and B.

      await repository.reorder(a.id, prevKey: c.sortKey, nextKey: b.sortKey);

      expect(await titles(Shelf.active), ['C', 'A', 'B']);
    });
  });

  group('copies', () {
    test('a copy carries text, pigment, and labels, but not pin or reminder', () async {
      await seedIfEmpty(db.noteDao);
      final passport = (await db.noteDao.loadShelf(
        Shelf.active,
      )).firstWhere((n) => n.title == 'Renew passport');

      final copy = await repository.duplicate(passport.id);

      expect(copy.id, isNot(passport.id));
      expect(copy.body, passport.body);
      expect(copy.pigment, passport.pigment);
      expect(copy.labels.map((l) => l.name), ['Admin']);
      expect(copy.hasReminder, isFalse);
      expect(copy.pinned, isFalse);
    });

    test('a copy of a checklist keeps items, order, and checked state', () async {
      await seedIfEmpty(db.noteDao);
      final groceries = (await db.noteDao.loadShelf(
        Shelf.active,
      )).firstWhere((n) => n.title == 'Groceries');

      final copy = await repository.duplicate(groceries.id);

      expect(
        copy.items.map((i) => (i.text, i.checked)),
        groceries.items.map((i) => (i.text, i.checked)),
      );
      expect(
        copy.items.map((i) => i.id).toSet().intersection(
          groceries.items.map((i) => i.id).toSet(),
        ),
        isEmpty,
      );
    });

    test('the copy lands at the top of the unpinned notes', () async {
      await seedIfEmpty(db.noteDao);
      final bike = (await db.noteDao.loadShelf(
        Shelf.active,
      )).firstWhere((n) => n.title == 'Bike');

      await repository.duplicate(bike.id);

      final active = await db.noteDao.loadShelf(Shelf.active);
      // Index 0 is the pinned note; the copy sits directly below it.
      expect(active[0].pinned, isTrue);
      expect(active[1].title, 'Bike');
      expect(active[1].id, isNot(bike.id));
    });
  });

  group('bulk edits', () {
    test('pin, archive, and recolour apply to every selected note', () async {
      final a = await repository.create(title: 'A');
      final b = await repository.create(title: 'B');
      final c = await repository.create(title: 'C');

      await repository.setPinnedMany([a.id, b.id], pinned: true);
      await repository.setPigmentMany([a.id, c.id], Pigment.indigo);
      await repository.setArchivedMany([c.id], archived: true);

      final loadedA = (await repository.load(a.id))!;
      final loadedB = (await repository.load(b.id))!;
      final loadedC = (await repository.load(c.id))!;
      expect(loadedA.pinned && loadedB.pinned, isTrue);
      expect(loadedA.pigment, Pigment.indigo);
      expect(loadedB.pigment, Pigment.graphite);
      expect(loadedC.pigment, Pigment.indigo);
      expect(loadedC.archived, isTrue);
    });

    test('undo of a recolour restores each note to its own pigment', () async {
      final a = await repository.create(title: 'A', pigment: Pigment.amber);
      final b = await repository.create(title: 'B', pigment: Pigment.plum);
      final previous = {a.id: a.pigment, b.id: b.pigment};

      await repository.setPigmentMany([a.id, b.id], Pigment.moss);
      await repository.restorePigments(previous);

      expect((await repository.load(a.id))!.pigment, Pigment.amber);
      expect((await repository.load(b.id))!.pigment, Pigment.plum);
    });

    test('undo of a pin restores mixed pin states', () async {
      final a = await repository.create(title: 'A');
      final b = await repository.create(title: 'B');
      await repository.setPinned(a.id, pinned: true);
      final previous = {a.id: true, b.id: false};

      await repository.setPinnedMany([a.id, b.id], pinned: false);
      await repository.restorePinned(previous);

      expect((await repository.load(a.id))!.pinned, isTrue);
      expect((await repository.load(b.id))!.pinned, isFalse);
    });

    test('deleteMany and restoreMany round-trip through the trash', () async {
      final a = await repository.create(title: 'A');
      final b = await repository.create(title: 'B');

      await repository.deleteMany([a.id, b.id]);
      expect(await titles(Shelf.active), isEmpty);
      expect(await titles(Shelf.trash), hasLength(2));

      await repository.restoreMany([a.id, b.id]);
      expect(await titles(Shelf.active), ['B', 'A']);
      expect(await titles(Shelf.trash), isEmpty);
    });
  });

  group('delete forever', () {
    test('removes a trashed note and cascades to its items', () async {
      await seedIfEmpty(db.noteDao);
      final groceries = (await db.noteDao.loadShelf(
        Shelf.active,
      )).firstWhere((n) => n.title == 'Groceries');
      await repository.delete(groceries.id);

      await repository.deleteForever(groceries.id);

      expect(await repository.load(groceries.id), isNull);
      final items = await (db.select(
        db.checklistItems,
      )..where((t) => t.noteId.equals(groceries.id))).get();
      expect(items, isEmpty);
    });
  });

  group('blank captures', () {
    test('an untouched note is removed outright, not trashed', () async {
      final note = await repository.create();

      final removed = await repository.discardIfBlank(note.id);

      expect(removed, isTrue);
      expect(await repository.load(note.id), isNull);
      expect(await titles(Shelf.trash), isEmpty);
    });

    test('a note with any text is kept', () async {
      final note = await repository.create(body: 'Keep me');

      final removed = await repository.discardIfBlank(note.id);

      expect(removed, isFalse);
      expect(await repository.load(note.id), isNotNull);
    });

    test('whitespace alone counts as blank', () async {
      final note = await repository.create(title: '   ', body: '\n\n');

      expect(await repository.discardIfBlank(note.id), isTrue);
    });
  });

  group('seed', () {
    test('writes starter notes once and only into an empty database', () async {
      await seedIfEmpty(db.noteDao);
      final first = await repository.count();

      await seedIfEmpty(db.noteDao);

      expect(first, 8);
      expect(await repository.count(), 8);
    });

    test('does not come back once every note is deleted', () async {
      await seedIfEmpty(db.noteDao);
      for (final note in await db.noteDao.loadShelf(Shelf.active)) {
        await repository.delete(note.id);
      }
      await repository.emptyTrash();

      await seedIfEmpty(db.noteDao);

      expect(await repository.count(), 0);
    });

    test('leaves an install that already holds notes alone', () async {
      await repository.create(title: 'Mine');

      await seedIfEmpty(db.noteDao);
      await repository.delete(
        (await db.noteDao.loadShelf(Shelf.active)).single.id,
      );
      await repository.emptyTrash();
      await seedIfEmpty(db.noteDao);

      expect(await repository.count(), 0);
    });

    test('attaches labels and keeps checklist items in order', () async {
      await seedIfEmpty(db.noteDao);
      final notes = await db.noteDao.loadShelf(Shelf.active);

      final passport = notes.firstWhere((n) => n.title == 'Renew passport');
      expect(passport.labels.map((l) => l.name), ['Admin']);
      expect(passport.hasReminder, isTrue);

      final groceries = notes.firstWhere((n) => n.title == 'Groceries');
      expect(groceries.items.map((i) => i.text), [
        'Oat milk',
        'Sourdough',
        'Eggs',
        'Coffee beans — the dark roast',
        'Chili oil',
      ]);
    });
  });

  test('watch emits again after a change', () async {
    final emissions = <int>[];
    final subscription = repository
        .watch(Shelf.active)
        .listen((notes) => emissions.add(notes.length));

    await pumpEventQueue();
    await repository.create(title: 'Live update');
    await pumpEventQueue();

    expect(emissions.first, 0);
    expect(emissions.last, 1);
    await subscription.cancel();
  });
}
