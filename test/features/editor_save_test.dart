import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/core/theme/app_theme.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/data/repository/note_repository.dart';
import 'package:notes/features/editor/editor_screen.dart';

/// Reading a note is not editing it. "Edited" times and the sync flag must
/// only move when the text actually changed.
void main() {
  late AppDatabase db;
  late NoteRepository repository;

  const body = 'Rear brake pads are down to the metal.';

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

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> openThenClose(
    WidgetTester tester,
    String noteId, {
    Future<void> Function()? whileOpen,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: EditorScreen(noteId: noteId),
        ),
      ),
    );
    await settle(tester);
    await whileOpen?.call();

    // Replacing the tree disposes the editor, which saves on the way out.
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  }

  testWidgets('closing a note that was only read leaves it untouched', (
    tester,
  ) async {
    final before = (await tester.runAsync(
      () => repository.create(title: 'Bike', body: body),
    ))!;
    // Enough time that a fresh stamp would differ.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );

    await openThenClose(tester, before.id);

    final after = (await tester.runAsync(() => repository.load(before.id)))!;
    expect(after.updatedAt, before.updatedAt);
  });

  testWidgets('closing after an edit saves it and moves the edited time', (
    tester,
  ) async {
    final before = (await tester.runAsync(
      () => repository.create(title: 'Bike', body: body),
    ))!;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );

    await openThenClose(
      tester,
      before.id,
      whileOpen: () => tester.enterText(
        find.widgetWithText(TextField, body),
        'Front pads too.',
      ),
    );

    final after = (await tester.runAsync(() => repository.load(before.id)))!;
    expect(after.body, 'Front pads too.');
    expect(after.updatedAt.isAfter(before.updatedAt), isTrue);
  });
}
