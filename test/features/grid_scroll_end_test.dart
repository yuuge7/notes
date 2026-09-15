import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/core/theme/app_theme.dart';
import 'package:notes/core/util/ids.dart';
import 'package:notes/core/util/sort_key.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/db/note_dao.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/features/notes/notes_screen.dart';
import 'package:notes/features/shelf/shelf_screen.dart';

/// Every note on the grid can be scrolled into view, whatever mix of section
/// sizes the days produce.
///
/// Guards a masonry sliver bug: a section with fewer notes than columns left
/// its empty column at an infinite offset, and once the section was scrolled
/// past the cache extent the sliver pulled the scroll position back, so the
/// grid stopped short of its end.
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

  /// Writes notes under consecutive days, [counts] notes per day, newest day
  /// first. Bodies vary in length so the columns come out uneven.
  Future<List<String>> insertDays(List<int> counts, {int pinned = 0}) async {
    final now = DateTime.now();
    final titles = <String>[];
    var key = SortKey.first;
    var n = 0;
    Future<void> add(DateTime at, {bool pin = false}) async {
      final title = 'Note $n';
      final body = List.filled(1 + (n * 7) % 5, 'A line of text here.').join(' ');
      await db.noteDao.insertNote(
        NotesCompanion.insert(
          id: newId(),
          sortKey: key,
          createdAtMs: at.millisecondsSinceEpoch,
          updatedAtMs: at.millisecondsSinceEpoch,
          title: Value(title),
          body: Value(body),
          pinned: Value(pin),
        ),
      );
      titles.add(title);
      key = SortKey.after(key);
      n++;
    }

    for (var i = 0; i < pinned; i++) {
      await add(now, pin: true);
    }
    for (var day = 0; day < counts.length; day++) {
      for (var i = 0; i < counts[day]; i++) {
        await add(DateTime(now.year, now.month, now.day - day * 2, 12, 60 - i));
      }
    }
    return titles;
  }

  Future<void> pumpPhone(WidgetTester tester) async {
    // A 1080x2400 phone at 420dpi with gesture navigation.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    tester.view.padding = const FakeViewPadding(top: 63, bottom: 63);
    tester.view.viewPadding = const FakeViewPadding(top: 63, bottom: 63);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const NotesScreen(),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Finder gridScrollable() => find.descendant(
    of: find.byType(CustomScrollView),
    matching: find.byType(Scrollable),
  );

  ScrollPosition gridPosition(WidgetTester tester) =>
      tester.state<ScrollableState>(gridScrollable()).position;

  /// Drags the grid a step at a time in [direction] until it stops moving,
  /// and returns every note title that was on screen along the way.
  Future<Set<String>> dragToEnd(
    WidgetTester tester,
    List<String> titles, {
    required double direction,
  }) async {
    final seen = <String>{};
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    var last = double.nan;
    for (var step = 0; step < 400; step++) {
      for (final title in titles) {
        final finder = find.text(title);
        if (finder.evaluate().isEmpty) continue;
        final rect = tester.getRect(finder);
        if (rect.top >= 0 && rect.bottom <= screen.height) seen.add(title);
      }
      final pixels = gridPosition(tester).pixels;
      if (pixels == last) break;
      last = pixels;
      await tester.drag(gridScrollable(), Offset(0, direction * 240));
      await tester.pump(const Duration(milliseconds: 16));
    }
    return seen;
  }

  for (final (name, counts, pinned) in [
    ('one pinned note, then days of two', [2, 2, 2, 2, 2], 1),
    ('single-note days between fuller ones', [3, 1, 4, 1, 5, 1, 2], 0),
    ('every day holds one note', [1, 1, 1, 1, 1, 1, 1, 1], 1),
    ('long sections', [9, 12, 7], 3),
  ]) {
    testWidgets('the grid scrolls to its end and back: $name', (tester) async {
      final titles = await insertDays(counts, pinned: pinned);
      await pumpPhone(tester);

      final down = await dragToEnd(tester, titles, direction: -1);
      final position = gridPosition(tester);
      expect(position.pixels, closeTo(position.maxScrollExtent, 0.5));

      // The last note clears the compose bar.
      final lastNote = tester.getRect(find.text(titles.last));
      final bar = tester.getRect(find.text('Take a note'));
      expect(lastNote.bottom, lessThan(bar.top));

      final up = await dragToEnd(tester, titles, direction: 1);
      expect(gridPosition(tester).pixels, 0);
      expect({...down, ...up}, titles.toSet());
    });
  }

  testWidgets('the archive scrolls to its end and back', (tester) async {
    await insertDays([40]);
    for (final note in await db.noteDao.loadShelf(Shelf.active)) {
      await db.noteDao.updateNote(
        note.id,
        const NotesCompanion(archived: Value(true)),
      );
    }
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ShelfScreen(shelf: Shelf.archived),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 50));
    }
    final scrollable = find.byType(Scrollable).first;
    ScrollPosition position() =>
        tester.state<ScrollableState>(scrollable).position;
    var last = double.nan;
    for (var step = 0; step < 400 && position().pixels != last; step++) {
      last = position().pixels;
      await tester.drag(scrollable, const Offset(0, -240));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(position().pixels, closeTo(position().maxScrollExtent, 0.5));
  });
}
