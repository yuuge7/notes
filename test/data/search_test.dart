import 'dart:math';

import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/core/util/ids.dart';
import 'package:notes/core/util/sort_key.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/db/search_dao.dart';
import 'package:notes/data/repository/checklist_repository.dart';
import 'package:notes/data/repository/label_repository.dart';
import 'package:notes/data/repository/note_repository.dart';
import 'package:notes/data/repository/search_repository.dart';
import 'package:notes/domain/model/note_type.dart';
import 'package:notes/domain/model/pigment.dart';
import 'package:notes/domain/model/search.dart';

void main() {
  late AppDatabase db;
  late NoteRepository notes;
  late ChecklistRepository lists;
  late LabelRepository labels;
  late SearchRepository search;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    notes = NoteRepository(db.noteDao);
    lists = ChecklistRepository(db.noteDao);
    labels = LabelRepository(db.noteDao);
    search = SearchRepository(db.searchDao);
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<String>> titles(
    String text, {
    NoteKind? kind,
    Pigment? pigment,
    String? labelId,
  }) async => [
    for (final note in (await search.search(
      SearchQuery(text: text, kind: kind, pigment: pigment, labelId: labelId),
    )).notes)
      note.title,
  ];

  group('matching', () {
    test('finds words in titles, bodies, list items, and labels', () async {
      await notes.create(title: 'Bike', body: 'Rear brake pads');
      final groceries = await notes.create(
        type: NoteType.checklist,
        title: 'Groceries',
      );
      await lists.add(groceries.id, text: 'Sourdough');
      final passport = await notes.create(title: 'Passport');
      final admin = await labels.create('Admin');
      await labels.setOnNotes([passport.id], admin.id, on: true);

      expect(await titles('bike'), ['Bike']);
      expect(await titles('brake'), ['Bike']);
      expect(await titles('sourdough'), ['Groceries']);
      expect(await titles('admin'), ['Passport']);
    });

    test('matches the start of a word while it is being typed', () async {
      await notes.create(title: 'Bike', body: 'Rear brake pads');

      expect(await titles('bra'), ['Bike']);
      expect(await titles('rake'), isEmpty);
    });

    test('every word has to match', () async {
      await notes.create(title: 'Bike', body: 'Rear brake pads');

      expect(await titles('rear pads'), ['Bike']);
      expect(await titles('rear eggs'), isEmpty);
    });

    test('ignores case and accents', () async {
      await notes.create(title: 'Șoseaua Kiseleff');

      expect(await titles('soseaua'), ['Șoseaua Kiseleff']);
      expect(await titles('ȘOSEA'), ['Șoseaua Kiseleff']);
    });

    test('words that look like query operators are searched for', () async {
      await notes.create(title: 'Salt OR pepper');

      expect(await titles('or'), ['Salt OR pepper']);
      expect(await titles('NEAR'), isEmpty);
    });

    test('punctuation alone searches for nothing', () async {
      await notes.create(title: 'Bike');

      expect(await titles('!!! ...'), isEmpty);
    });

    test('a match in the title ranks above one in a body', () async {
      await notes.create(title: 'Lamp');
      // Newer, so it would come first in grid order.
      await notes.create(title: 'Shopping', body: 'A bulb for the lamp');

      expect(await titles('lamp'), ['Lamp', 'Shopping']);
    });
  });

  test('leaves out the trash and lists archived matches last', () async {
    final archived = await notes.create(title: 'Tent pegs');
    await notes.setArchived(archived.id, archived: true);
    await notes.create(title: 'Tent poles');
    final trashed = await notes.create(title: 'Tent fly');
    await notes.delete(trashed.id);

    expect(await titles('tent'), ['Tent poles', 'Tent pegs']);
  });

  group('keeping up with edits', () {
    test('an edited title is found by its new words only', () async {
      final note = await notes.create(title: 'Draft');
      await notes.saveText(note.id, title: 'Final');

      expect(await titles('final'), ['Final']);
      expect(await titles('draft'), isEmpty);
    });

    test('a removed list item is no longer found', () async {
      final note = await notes.create(
        type: NoteType.checklist,
        title: 'Groceries',
      );
      final item = await lists.add(note.id, text: 'Chili oil');

      expect(await titles('chili'), ['Groceries']);
      await lists.remove(note.id, item.id);
      expect(await titles('chili'), isEmpty);
    });

    test('a renamed label finds its notes by the new name', () async {
      final note = await notes.create(title: 'Boiler');
      final home = await labels.create('Home');
      await labels.setOnNotes([note.id], home.id, on: true);

      await labels.rename(home.id, 'Flat');

      expect(await titles('flat'), ['Boiler']);
      expect(await titles('home'), isEmpty);
    });

    test('a label taken off or deleted no longer finds the note', () async {
      final a = await notes.create(title: 'Boiler');
      final b = await notes.create(title: 'Radiator');
      final home = await labels.create('Home');
      await labels.setOnNotes([a.id, b.id], home.id, on: true);

      await labels.setOnNotes([a.id], home.id, on: false);
      expect(await titles('home'), ['Radiator']);

      await labels.delete(home.id);
      expect(await titles('home'), isEmpty);
    });

    test('a note deleted forever leaves nothing behind in the index', () async {
      final kettle = await notes.create(title: 'Kettle');
      await notes.delete(kettle.id);
      await notes.deleteForever(kettle.id);
      // A new note can take the freed rowid; it must not inherit the old text.
      await notes.create(title: 'Toaster');

      expect(await titles('kettle'), isEmpty);
      expect(await titles('toaster'), ['Toaster']);
    });

    test('a copy is found alongside its original', () async {
      final kettle = await notes.create(title: 'Kettle');
      await notes.duplicate(kettle.id);

      expect(await titles('kettle'), ['Kettle', 'Kettle']);
    });
  });

  group('filters', () {
    late String homeId;

    setUp(() async {
      final groceries = await notes.create(
        type: NoteType.checklist,
        title: 'Groceries',
        pigment: Pigment.amber,
      );
      final passport = await notes.create(
        title: 'Passport',
        pigment: Pigment.vermilion,
      );
      await db.noteDao.updateNote(
        passport.id,
        NotesCompanion(
          reminderAtMs: Value(DateTime(2026, 9, 16).millisecondsSinceEpoch),
        ),
      );
      await notes.create(title: 'Bike');
      homeId = (await labels.create('Home')).id;
      await labels.setOnNotes([groceries.id], homeId, on: true);
    });

    test('narrow to a kind of note', () async {
      expect(await titles('', kind: NoteKind.list), ['Groceries']);
      expect(await titles('', kind: NoteKind.reminder), ['Passport']);
      expect(await titles('', kind: NoteKind.image), isEmpty);
    });

    test('narrow to a colour', () async {
      expect(await titles('', pigment: Pigment.amber), ['Groceries']);
    });

    test('narrow to a label', () async {
      expect(await titles('', labelId: homeId), ['Groceries']);
    });

    test('combine with typed words', () async {
      expect(await titles('gro', pigment: Pigment.amber), ['Groceries']);
      expect(await titles('gro', pigment: Pigment.vermilion), isEmpty);
    });

    test('offer only what some note outside the trash has', () async {
      final trashed = await notes.create(title: 'Old', pigment: Pigment.plum);
      final admin = await labels.create('Admin');
      await labels.setOnNotes([trashed.id], admin.id, on: true);
      await notes.delete(trashed.id);

      final facets = await search.watchFacets().first;

      expect(facets.kinds, [NoteKind.list, NoteKind.reminder]);
      expect(facets.pigments, [
        Pigment.graphite,
        Pigment.vermilion,
        Pigment.amber,
      ]);
      expect([for (final label in facets.labels) label.name], ['Home']);
    });
  });

  test('counts every match but loads at most the limit', () async {
    for (var i = 0; i < SearchDao.limit + 5; i++) {
      await notes.create(title: 'Box $i');
    }

    final results = await search.search(const SearchQuery(text: 'box'));

    expect(results.notes, hasLength(SearchDao.limit));
    expect(results.total, SearchDao.limit + 5);
  });

  group('recent searches', () {
    test('keeps the last three, newest first', () async {
      for (final query in ['tent', 'bike', 'lamp', 'boiler']) {
        await search.remember(query);
      }

      expect(await search.watchRecent().first, ['boiler', 'lamp', 'bike']);
    });

    test('the same search typed again moves to the top once', () async {
      await search.remember('Bike');
      await search.remember('tent');
      await search.remember('  bike ');

      expect(await search.watchRecent().first, ['bike', 'tent']);
    });

    test('blank searches are not kept, and clearing forgets all', () async {
      await search.remember('   ');
      expect(await search.watchRecent().first, isEmpty);

      await search.remember('tent');
      await search.clearRecent();
      expect(await search.watchRecent().first, isEmpty);
    });
  });

  test('searches 5,000 notes in under 50ms', tags: 'perf', () async {
    const noteCount = 5000;
    final random = Random(7);
    const syllables = [
      'ka', 'lo', 'mi', 'ra', 'se', 'tu', 'vo', 'ne', 'pa', 'di', //
      'bre', 'sto', 'gra', 'pli', 'mur', 'fen', 'dal', 'kor', 'sil', 'tam',
    ];
    String word() => [
      for (var i = 0; i < 2 + random.nextInt(2); i++)
        syllables[random.nextInt(syllables.length)],
    ].join();
    String words(int count) => [for (var i = 0; i < count; i++) word()].join(' ');

    final now = DateTime.now().millisecondsSinceEpoch;
    var key = SortKey.first;
    final noteRows = <NotesCompanion>[];
    final itemRows = <ChecklistItemsCompanion>[];
    for (var i = 0; i < noteCount; i++) {
      final id = newId();
      final isList = i % 5 == 0;
      noteRows.add(
        NotesCompanion.insert(
          id: id,
          sortKey: key,
          createdAtMs: now,
          updatedAtMs: now,
          type: Value(isList ? NoteType.checklist : NoteType.text),
          title: Value(words(3)),
          body: Value(isList ? '' : words(40)),
          pigment: Value(Pigment.values[i % Pigment.values.length]),
        ),
      );
      if (isList) {
        for (var j = 0; j < 8; j++) {
          itemRows.add(
            ChecklistItemsCompanion.insert(
              id: newId(),
              noteId: id,
              sortKey: 'n$j',
              updatedAtMs: now,
              content: Value(words(3)),
            ),
          );
        }
      }
      key = SortKey.after(key);
    }
    await db.batch((batch) {
      batch
        ..insertAll(db.notes, noteRows)
        ..insertAll(db.checklistItems, itemRows);
    });

    const queries = [
      SearchQuery(text: 'b'),
      SearchQuery(text: 'bre'),
      SearchQuery(text: 'bresto'),
      SearchQuery(text: 'ka lo'),
      SearchQuery(text: 'gra', pigment: Pigment.moss),
      SearchQuery(kind: NoteKind.list),
    ];
    final timings = <String, int>{};
    for (final query in queries) {
      await search.search(query);
      final runs = <int>[];
      for (var run = 0; run < 5; run++) {
        final watch = Stopwatch()..start();
        await search.search(query);
        runs.add(watch.elapsedMicroseconds);
      }
      runs.sort();
      timings['${query.text}|${query.kind?.name}|${query.pigment?.name}'] =
          runs[runs.length ~/ 2];
    }

    // Recorded so the numbers can go into the plan.
    // ignore: avoid_print
    print({
      for (final MapEntry(:key, :value) in timings.entries)
        key: '${(value / 1000).toStringAsFixed(1)}ms',
    });
    for (final median in timings.values) {
      expect(median, lessThan(50000));
    }
  });
}
