import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/core/theme/app_theme.dart';
import 'package:notes/core/util/ids.dart';
import 'package:notes/core/util/sort_key.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/db/note_dao.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/data/repository/label_repository.dart';
import 'package:notes/data/seed.dart';
import 'package:notes/features/notes/notes_providers.dart';
import 'package:notes/features/notes/notes_screen.dart';

/// A shelf of hundreds loads a page at a time: the grid reads the next page as
/// its end comes near, and a move at the end of what is loaded still lands
/// before the notes not loaded yet.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  /// [count] notes titled `Note 1` onwards, in that order, all written today.
  /// The first [pinned] are pinned.
  Future<List<String>> write(int count, {int pinned = 0}) async {
    // No starter notes on top of these.
    await db.preferenceDao.write('seeded', 'true');
    final now = DateTime.now().millisecondsSinceEpoch;
    final keys = SortKey.spread(count);
    final ids = [for (var i = 0; i < count; i++) newId()];
    await db.batch((batch) {
      batch.insertAll(db.notes, [
        for (var i = 0; i < count; i++)
          NotesCompanion.insert(
            id: ids[i],
            title: Value('Note ${i + 1}'),
            sortKey: keys[i],
            pinned: Value(i < pinned),
            createdAtMs: now - i,
            updatedAtMs: now,
          ),
      ]);
    });
    return ids;
  }

  group('a page of a shelf', () {
    test('holds the first notes in order, and counts them all', () async {
      await write(250, pinned: 2);

      final page = await db.noteDao.loadShelfPage(Shelf.active, 100);

      expect(page.notes, hasLength(100));
      expect(page.total, 250);
      expect(page.hasMore, isTrue);
      expect(page.notes.take(3).map((note) => note.title), [
        'Note 1',
        'Note 2',
        'Note 3',
      ]);
      expect(page.notes.last.title, 'Note 100');
      final next = (await db.noteDao.loadShelf(Shelf.active))[100];
      expect(page.after, (sortKey: next.sortKey, pinned: false));
    });

    test('says when the page ends among the pinned notes', () async {
      await write(10, pinned: 5);

      final page = await db.noteDao.loadShelfPage(Shelf.active, 3);

      expect(page.after?.pinned, isTrue);
    });

    test('is the whole shelf when it fits', () async {
      await write(40);

      final page = await db.noteDao.loadShelfPage(Shelf.active, 100);

      expect(page.notes, hasLength(40));
      expect(page.hasMore, isFalse);
      expect(page.after, isNull);
    });

    test('of a label holds only the notes wearing it', () async {
      final ids = await write(30);
      final labels = LabelRepository(db.noteDao);
      final label = await labels.create('Tiles');
      await labels.setOnNotes(ids.take(12), label.id, on: true);

      final page = await db.noteDao.loadLabelShelfPage(label.id, 5);

      expect(page.notes, hasLength(5));
      expect(page.total, 12);
    });
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<ProviderContainer> pumpGrid(
    WidgetTester tester, {
    bool fixedWindow = false,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          if (fixedWindow) noteWindowProvider.overrideWith2((_) => _OnePage()),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const NotesScreen()),
      ),
    );
    await settle(tester);
    return ProviderScope.containerOf(tester.element(find.byType(NotesScreen)));
  }

  testWidgets('the grid counts every note and loads more near its end', (
    tester,
  ) async {
    await tester.runAsync(() => write(250));
    final container = await pumpGrid(tester);

    expect(find.text('250 NOTES'), findsOneWidget);
    expect(find.text('Note 1'), findsOneWidget);
    expect(find.text('Note 250'), findsNothing);

    for (var i = 0; i < 80 && find.text('Note 250').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -1500));
      await settle(tester);
    }

    expect(find.text('Note 250'), findsOneWidget);
    expect(
      container.read(noteWindowProvider(Shelf.active.name)),
      greaterThanOrEqualTo(250),
    );
  });

  testWidgets(
    'a note moved to the end of what is loaded stays before the rest',
    (tester) async {
      final handle = tester.ensureSemantics();
      await tester.runAsync(() => write(notePageSize + 1));
      // One page and no more, so Note 101 stays unloaded.
      await pumpGrid(tester, fixedWindow: true);
      expect(find.text('Note 101'), findsNothing);
      await tester.ensureVisible(find.text('Note 99'));
      await settle(tester);

      final node = tester.getSemantics(
        find.bySemanticsLabel(RegExp(r'^Note 99$')),
      );
      node.owner!.performAction(
        node.id,
        SemanticsAction.customAction,
        CustomSemanticsAction.getIdentifier(
          const CustomSemanticsAction(label: 'Move later'),
        ),
      );
      await settle(tester);

      final titles = [
        for (final note in (await tester.runAsync(
          () => db.noteDao.loadShelf(Shelf.active),
        ))!)
          note.title,
      ];
      expect(titles.skip(97), ['Note 98', 'Note 100', 'Note 99', 'Note 101']);
      handle.dispose();
    },
  );

  test('the starter notes are not needed for these tests', () async {
    // Guards the helper above: with the seeded flag set, a start writes none.
    await write(1);
    await seedIfEmpty(db.noteDao);
    expect(await db.noteDao.countNotes(), 1);
  });
}

/// A window that never grows past its first page.
class _OnePage extends NoteWindow {
  @override
  void grow() {}
}
