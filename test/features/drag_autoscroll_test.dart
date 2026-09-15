import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/core/theme/app_theme.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/features/notes/notes_screen.dart';

/// A note held near the edge of the grid scrolls it, so a note can be moved
/// to a place that was off screen when the drag began.
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

  Future<void> pumpShortGrid(WidgetTester tester) async {
    // Short enough that the seeded notes do not fit, so the grid can scroll.
    tester.view.physicalSize = const Size(400, 800);
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
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  ScrollPosition gridPosition(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        ),
      )
      .position;

  testWidgets('holding a dragged note at the bottom edge scrolls the grid', (
    tester,
  ) async {
    await pumpShortGrid(tester);
    expect(gridPosition(tester).pixels, 0);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Flat viewing — Aurel Vlaicu 12')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await tester.pump();
    await gesture.moveTo(const Offset(200, 795));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 1));
    await tester.pump(const Duration(milliseconds: 500));

    expect(gridPosition(tester).pixels, greaterThan(0));

    await gesture.up();
    await tester.pump();
    final whereItStopped = gridPosition(tester).pixels;
    await tester.pump(const Duration(milliseconds: 500));

    expect(gridPosition(tester).pixels, whereItStopped);
  });

  testWidgets('dragging in the middle of the grid does not scroll it', (
    tester,
  ) async {
    await pumpShortGrid(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Flat viewing — Aurel Vlaicu 12')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await tester.pump();
    await gesture.moveTo(const Offset(200, 400));
    await tester.pump(const Duration(milliseconds: 500));

    expect(gridPosition(tester).pixels, 0);

    await gesture.up();
    await tester.pump();
  });
}
