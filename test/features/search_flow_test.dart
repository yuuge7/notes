import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/core/router/router.dart';
import 'package:notes/core/theme/app_theme.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/db/note_dao.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/data/repository/note_repository.dart';

/// Searching the seeded notes the way a person would: from the grid, by
/// typing, by filters alone, and by picking a search from before.
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

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> openSearch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: buildRouter(),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.byTooltip('Search'));
    await settle(tester);
  }

  /// The words drawn with a highlight anywhere on screen.
  List<String> marked(WidgetTester tester) => [
    for (final text in tester.widgetList<Text>(find.byType(Text)))
      if (text.textSpan case final TextSpan rich)
        for (final span in rich.children ?? const <InlineSpan>[])
          if (span is TextSpan && span.style?.backgroundColor != null)
            span.text!,
  ];

  testWidgets('typing finds a note by its body and marks the word', (
    tester,
  ) async {
    await openSearch(tester);

    await tester.enterText(find.byType(TextField), 'brak');
    await settle(tester);

    expect(find.text('1 NOTE'), findsOneWidget);
    expect(find.text('Bike'), findsOneWidget);
    expect(find.text('Dentist'), findsNothing);
    expect(marked(tester), ['brak']);
  });

  testWidgets('a label name finds the notes wearing it', (tester) async {
    await openSearch(tester);

    await tester.enterText(find.byType(TextField), 'admin');
    await settle(tester);

    expect(find.text('2 NOTES'), findsOneWidget);
    expect(find.text('Renew passport'), findsOneWidget);
    expect(find.text('Dentist'), findsOneWidget);
  });

  testWidgets('a filter alone lists notes, and Any type clears it', (
    tester,
  ) async {
    await openSearch(tester);

    await tester.tap(find.text('Type'));
    await settle(tester);
    await tester.tap(find.text('Lists'));
    await settle(tester);

    expect(find.text('2 NOTES'), findsOneWidget);
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Plants while away'), findsOneWidget);

    await tester.tap(find.text('Lists'));
    await settle(tester);
    await tester.tap(find.text('Any type'));
    await settle(tester);

    expect(find.text('Find anything you wrote'), findsOneWidget);
  });

  testWidgets('a search sent with the keyboard is offered again', (
    tester,
  ) async {
    await openSearch(tester);

    await tester.enterText(find.byType(TextField), 'passport');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
    await tester.tap(find.byTooltip('Clear search'));
    await settle(tester);

    expect(find.text('RECENT'), findsOneWidget);
    await tester.tap(find.text('passport'));
    await settle(tester);

    expect(find.text('Renew passport'), findsOneWidget);
  });

  testWidgets('no match says what was searched for', (tester) async {
    await openSearch(tester);

    await tester.enterText(find.byType(TextField), 'zzqx');
    await settle(tester);

    expect(find.text('Nothing matches “zzqx”'), findsOneWidget);
  });

  testWidgets('archived matches come after the rest, under Archive', (
    tester,
  ) async {
    // Opening search from the grid seeds the notes, so archive after.
    await openSearch(tester);
    await tester.runAsync(() async {
      final notes = await db.noteDao.loadShelf(Shelf.active);
      await NoteRepository(db.noteDao).setArchived(
        notes.firstWhere((note) => note.title == 'Dentist').id,
        archived: true,
      );
    });

    await tester.enterText(find.byType(TextField), 'admin');
    await settle(tester);

    expect(find.text('ARCHIVE'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Renew passport')).dy,
      lessThan(tester.getTopLeft(find.text('Dentist')).dy),
    );
  });

  testWidgets('back from search returns to the grid', (tester) async {
    await openSearch(tester);

    await tester.tap(find.byTooltip('Back'));
    await settle(tester);

    expect(find.text('8 NOTES'), findsOneWidget);
  });
}
