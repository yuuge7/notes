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

/// No control in the editor may look usable and do nothing.
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
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpEditor(WidgetTester tester, {String? noteId}) async {
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
  }

  PopupMenuItem<Object?> menuItem(WidgetTester tester, String label) {
    return tester.widget<PopupMenuItem<Object?>>(
      find
          .ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
          )
          .first,
    );
  }

  testWidgets('on a blank new note, Share and Make a copy are not offered', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.tap(find.byTooltip('More'));
    await settle(tester);

    expect(menuItem(tester, 'Share').enabled, isFalse);
    expect(menuItem(tester, 'Make a copy').enabled, isFalse);
    expect(menuItem(tester, 'Delete').enabled, isTrue);
  });

  testWidgets('once the page holds text, Share and Make a copy are offered', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Write it down'),
      'Call the plumber',
    );
    await tester.tap(find.byTooltip('More'));
    await settle(tester);

    expect(menuItem(tester, 'Share').enabled, isTrue);
    expect(menuItem(tester, 'Make a copy').enabled, isTrue);
    await settle(tester);
  });

  testWidgets(
    'tapping the blank page asks for the keyboard even when the text is '
    'already focused',
    (tester) async {
      final note = (await tester.runAsync(
        () => NoteRepository(
          db.noteDao,
        ).create(title: 'Bike', body: 'Rear brake pads are down to the metal.'),
      ))!;
      await pumpEditor(tester, noteId: note.id);
      const blankPage = Offset(400, 1600);

      await tester.tapAt(blankPage);
      await settle(tester);

      // Back can put the keyboard away while the text keeps focus. A
      // second tap on the page must bring it back.
      tester.testTextInput.log.clear();
      await tester.tapAt(blankPage);
      await settle(tester);

      expect(
        tester.testTextInput.log.map((call) => call.method),
        contains('TextInput.show'),
      );
    },
  );
}
