import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/core/theme/app_theme.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/db/note_dao.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/features/notes/notes_screen.dart';

/// Reordering on the grid, by drag and by screen-reader action, checked
/// against the order the database actually stores.
///
/// Seeded unpinned order: today holds Groceries then Renew passport; yesterday
/// holds the untitled quote, Bike, and The Peregrine.
void main() {
  late AppDatabase db;

  const moveEarlier = CustomSemanticsAction(label: 'Move earlier');
  const moveLater = CustomSemanticsAction(label: 'Move later');

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

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpGrid(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
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
    await settle(tester);
  }

  Future<List<String>> unpinnedTitles() async => [
    for (final note in await db.noteDao.loadShelf(Shelf.active))
      if (!note.pinned) note.title,
  ];

  SemanticsNode cardNode(WidgetTester tester, String title) =>
      tester.getSemantics(find.bySemanticsLabel(RegExp('^$title\\.')));

  List<int> actionIds(SemanticsNode node) =>
      node.getSemanticsData().customSemanticsActionIds ?? const [];

  testWidgets('a screen reader can move a note later within its day', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpGrid(tester);

    final groceries = cardNode(tester, 'Groceries');
    groceries.owner!.performAction(
      groceries.id,
      SemanticsAction.customAction,
      CustomSemanticsAction.getIdentifier(moveLater),
    );
    await settle(tester);

    expect((await unpinnedTitles()).take(2), ['Renew passport', 'Groceries']);
    handle.dispose();
  });

  testWidgets('notes at the edge of a day only offer moves inside that day', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpGrid(tester);

    final first = actionIds(cardNode(tester, 'Groceries'));
    final last = actionIds(cardNode(tester, 'Renew passport'));

    expect(first, contains(CustomSemanticsAction.getIdentifier(moveLater)));
    expect(
      first,
      isNot(contains(CustomSemanticsAction.getIdentifier(moveEarlier))),
    );
    expect(last, contains(CustomSemanticsAction.getIdentifier(moveEarlier)));
    expect(
      last,
      isNot(contains(CustomSemanticsAction.getIdentifier(moveLater))),
    );
    handle.dispose();
  });

  testWidgets('dragging a note onto another in the same day moves it there', (
    tester,
  ) async {
    await pumpGrid(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Groceries')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    // The drag has started and selected the note; the header is now the
    // selection bar, so find the target only after that layout change.
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.text('Renew passport')));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 4));
    await tester.pump();
    await gesture.up();
    await settle(tester);

    expect((await unpinnedTitles()).take(2), ['Renew passport', 'Groceries']);
    expect(find.byTooltip('Clear selection'), findsNothing);
  });

  testWidgets('a note dropped on another day stays where it was', (
    tester,
  ) async {
    await pumpGrid(tester);
    final before = await unpinnedTitles();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Groceries')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.text('Bike')));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 4));
    await tester.pump();
    await gesture.up();
    await settle(tester);

    expect(await unpinnedTitles(), before);
    // The press still selected the note, as a plain long-press would.
    expect(find.byTooltip('Clear selection'), findsOneWidget);
  });
}
