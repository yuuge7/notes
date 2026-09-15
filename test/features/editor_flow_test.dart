import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/core/theme/app_theme.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/features/notes/notes_screen.dart';

/// End-to-end flows through the grid and the editor, against a real in-memory
/// database: what a person does, and what is stored afterwards.
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

  /// Lets database work run outside fake time, then advances frames far
  /// enough to cover the 400ms autosave debounce and the 220ms container
  /// transform.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpApp(WidgetTester tester) async {
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
    expect(find.text('8 NOTES'), findsOneWidget);
  }

  Future<void> closeEditor(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Back'));
    await settle(tester);
  }

  testWidgets('an edited note keeps its changes after the editor closes', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Bike'));
    await settle(tester);
    final body = find.widgetWithText(
      TextField,
      'Rear brake pads are down to the metal.',
    );
    expect(body, findsOneWidget);

    await tester.enterText(
      body,
      'Rear brake pads are down to the metal. Order a pair.',
    );
    await closeEditor(tester);

    expect(find.textContaining('Order a pair.'), findsOneWidget);
  });

  testWidgets('a note written from the compose bar lands in the grid', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Take a note'));
    await settle(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Write it down'),
      'Call the plumber about the kitchen tap',
    );
    await closeEditor(tester);

    expect(find.text('9 NOTES'), findsOneWidget);
    expect(
      find.text('Call the plumber about the kitchen tap'),
      findsOneWidget,
    );
  });

  testWidgets('opening a new note and backing out leaves nothing behind', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Take a note'));
    await settle(tester);
    await closeEditor(tester);

    expect(find.text('8 NOTES'), findsOneWidget);
    expect(find.text('Empty note'), findsNothing);
  });

  testWidgets('text typed and then cleared is discarded, not kept as blank', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Take a note'));
    await settle(tester);
    final field = find.widgetWithText(TextField, 'Write it down');
    await tester.enterText(field, 'Never mind');
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, '');
    await closeEditor(tester);

    expect(find.text('8 NOTES'), findsOneWidget);
    expect(find.text('Empty note'), findsNothing);
  });

  testWidgets('archiving from the editor removes the card and undo returns it', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Bike'));
    await settle(tester);
    await tester.tap(find.byTooltip('Archive'));
    await settle(tester);

    expect(find.text('7 NOTES'), findsOneWidget);
    expect(find.text('Note archived'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await settle(tester);

    expect(find.text('8 NOTES'), findsOneWidget);
    expect(find.text('Bike'), findsOneWidget);
  });

  testWidgets('deleting a selection moves it to the trash and undo restores it', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.longPress(find.text('Bike'));
    await tester.pump();
    await tester.tap(find.text('Dentist'));
    await tester.pump();
    await tester.tap(find.byTooltip('Delete'));
    await settle(tester);

    expect(find.text('6 NOTES'), findsOneWidget);
    expect(find.text('2 notes moved to trash'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await settle(tester);

    expect(find.text('8 NOTES'), findsOneWidget);
  });

  testWidgets('pinning from the editor moves the note under PINNED', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Bike'));
    await settle(tester);
    await tester.tap(find.byTooltip('Pin'));
    await settle(tester);
    expect(find.byTooltip('Unpin'), findsOneWidget);
    await closeEditor(tester);

    final pinnedHeader = tester.getTopLeft(find.text('PINNED')).dy;
    final todayHeader = tester.getTopLeft(find.text('TODAY')).dy;
    final bike = tester.getTopLeft(find.text('Bike')).dy;
    expect(bike, greaterThan(pinnedHeader));
    expect(bike, lessThan(todayHeader));
  });
}
