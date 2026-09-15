import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/core/theme/app_theme.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/db/note_dao.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/data/repository/checklist_repository.dart';
import 'package:notes/data/repository/note_repository.dart';
import 'package:notes/domain/model/note_type.dart';
import 'package:notes/features/editor/checklist_section.dart';
import 'package:notes/features/editor/editor_screen.dart';
import 'package:notes/features/notes/notes_screen.dart';

/// Writing a list the way people do: typing, Enter, backspace, ticking things
/// off, and changing their mind about checkboxes.
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

  void tallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> pump(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(theme: AppTheme.light(), home: home),
      ),
    );
    await settle(tester);
  }

  /// Unmounts the editor while the database is still open. Closing a list
  /// tidies its empty items, and the tear-down closes the database after.
  Future<void> closeEditor(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    // Closing may save pending items, tidy empty ones, and discard a blank
    // note: several transactions, so it gets more turns than a normal settle.
    for (var i = 0; i < 3; i++) {
      await settle(tester);
    }
  }

  Future<String> createList(WidgetTester tester, List<String> texts) async {
    return (await tester.runAsync(() async {
      final note = await NoteRepository(
        db.noteDao,
      ).create(type: NoteType.checklist, title: 'Groceries');
      final lists = ChecklistRepository(db.noteDao);
      for (final text in texts) {
        await lists.add(note.id, text: text);
      }
      return note.id;
    }))!;
  }

  Future<List<(String, int, bool)>> itemsOf(
    WidgetTester tester,
    String noteId,
  ) async {
    final items = (await tester.runAsync(
      () => ChecklistRepository(db.noteDao).items(noteId),
    ))!;
    return [for (final item in items) (item.text, item.indent, item.checked)];
  }

  TextEditingController controllerOf(WidgetTester tester, String text) =>
      tester.widget<TextField>(find.widgetWithText(TextField, text)).controller!;

  bool isFocused(WidgetTester tester, String text) => tester
      .widget<TextField>(find.widgetWithText(TextField, text))
      .focusNode!
      .hasFocus;

  testWidgets('a list started from the compose bar lands in the grid', (
    tester,
  ) async {
    tallScreen(tester);
    await pump(tester, const NotesScreen());

    await tester.tap(find.byTooltip('New list'));
    await settle(tester);
    expect(find.text('NEW LIST'), findsOneWidget);

    // Text the seeded notes do not already contain, so the card is findable.
    await tester.enterText(
      find.widgetWithText(TextField, 'List item'),
      'Birthday candles',
    );
    await settle(tester);
    await tester.tap(find.byTooltip('Back'));
    await settle(tester);

    expect(find.text('9 NOTES'), findsOneWidget);
    expect(find.text('Birthday candles'), findsOneWidget);
  });

  testWidgets('typing fast into a new list keeps every character in one item', (
    tester,
  ) async {
    tallScreen(tester);
    await pump(tester, const EditorScreen(startAsChecklist: true));

    // One character at a time with no frames between, the way a keyboard
    // burst arrives. The first item must already exist to receive them.
    final item = find.byType(TextField).last;
    const text = 'Oat milk';
    for (var i = 1; i <= text.length; i++) {
      await tester.enterText(item, text.substring(0, i));
    }
    await settle(tester);

    final notes = (await tester.runAsync(
      () => db.noteDao.loadShelf(Shelf.active),
    ))!;
    expect(notes, hasLength(1));
    expect(await itemsOf(tester, notes.single.id), [('Oat milk', 0, false)]);
    await closeEditor(tester);
  });

  testWidgets('backing out of an untouched new list leaves nothing behind', (
    tester,
  ) async {
    tallScreen(tester);
    await pump(tester, const NotesScreen());

    await tester.tap(find.byTooltip('New list'));
    await settle(tester);
    await tester.tap(find.byTooltip('Back'));
    await settle(tester);

    expect(find.text('8 NOTES'), findsOneWidget);
    expect(find.text('Empty note'), findsNothing);
  });

  testWidgets('archiving an untouched new list just closes it', (tester) async {
    tallScreen(tester);
    await pump(tester, const NotesScreen());

    await tester.tap(find.byTooltip('New list'));
    await settle(tester);
    await tester.tap(find.byTooltip('Archive'));
    await settle(tester);

    expect(find.text('8 NOTES'), findsOneWidget);
    expect(find.text('Note archived'), findsNothing);
  });

  testWidgets('dragging an item by its handle moves it above another', (
    tester,
  ) async {
    tallScreen(tester);
    final id = await createList(tester, ['First', 'Second', 'Third']);
    await pump(tester, EditorScreen(noteId: id));

    final handles = find.byIcon(Icons.drag_indicator);
    final start = tester.getCenter(handles.at(2));
    final target = tester.getCenter(handles.at(0)) - const Offset(0, 30);
    final gesture = await tester.startGesture(start);
    await tester.pump();
    // In steps, as a finger moves, to just above the first item.
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(Offset.lerp(start, target, i / 10)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await settle(tester);

    expect((await itemsOf(tester, id)).map((i) => i.$1), [
      'Third',
      'First',
      'Second',
    ]);
    await closeEditor(tester);
  });

  testWidgets('a screen reader can move an item down the list', (tester) async {
    tallScreen(tester);
    final id = await createList(tester, ['First', 'Second', 'Third']);
    await pump(tester, EditorScreen(noteId: id));
    final handle = tester.ensureSemantics();

    final row = tester.getSemantics(find.byType(ChecklistRow).first);
    row.owner!.performAction(
      row.id,
      SemanticsAction.customAction,
      CustomSemanticsAction.getIdentifier(
        const CustomSemanticsAction(label: 'Move down'),
      ),
    );
    await settle(tester);

    expect((await itemsOf(tester, id)).map((i) => i.$1), [
      'Second',
      'First',
      'Third',
    ]);
    handle.dispose();
    await closeEditor(tester);
  });

  testWidgets('Enter splits an item at the cursor and moves to the new line', (
    tester,
  ) async {
    tallScreen(tester);
    final id = await createList(tester, ['Oat milk', 'Sourdough']);
    await pump(tester, EditorScreen(noteId: id));

    await tester.showKeyboard(find.widgetWithText(TextField, 'Oat milk'));
    controllerOf(tester, 'Oat milk').selection = const TextSelection.collapsed(
      offset: 3,
    );
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await settle(tester);

    expect((await itemsOf(tester, id)).map((i) => i.$1), [
      'Oat',
      ' milk',
      'Sourdough',
    ]);
    expect(isFocused(tester, ' milk'), isTrue);
    await closeEditor(tester);
  });

  testWidgets('backspace in an empty item removes it and returns above', (
    tester,
  ) async {
    tallScreen(tester);
    final id = await createList(tester, ['Tea', '']);
    await pump(tester, EditorScreen(noteId: id));

    // The empty item is the one text field with nothing in it.
    await tester.showKeyboard(
      find.byWidgetPredicate(
        (w) => w is TextField && (w.controller?.text.isEmpty ?? false),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await settle(tester);

    expect(await itemsOf(tester, id), [('Tea', 0, false)]);
    expect(isFocused(tester, 'Tea'), isTrue);
    expect(controllerOf(tester, 'Tea').selection.baseOffset, 3);
    await closeEditor(tester);
  });

  testWidgets('a checked item folds into the checked section', (tester) async {
    tallScreen(tester);
    final id = await createList(tester, ['Eggs', 'Rye']);
    await pump(tester, EditorScreen(noteId: id));

    await tester.tap(find.byType(Checkbox).first);
    await settle(tester);

    expect(find.text('1 CHECKED ITEM'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Eggs'), findsNothing);

    await tester.tap(find.text('1 CHECKED ITEM'));
    await settle(tester);

    expect(find.widgetWithText(TextField, 'Eggs'), findsOneWidget);
    await closeEditor(tester);
  });

  testWidgets('a focused item can be indented under the one above', (
    tester,
  ) async {
    tallScreen(tester);
    final id = await createList(tester, ['Bakery', 'Sourdough']);
    await pump(tester, EditorScreen(noteId: id));

    await tester.showKeyboard(find.widgetWithText(TextField, 'Sourdough'));
    await settle(tester);
    await tester.tap(find.byTooltip('Indent'));
    await settle(tester);

    expect(await itemsOf(tester, id), [
      ('Bakery', 0, false),
      ('Sourdough', 1, false),
    ]);
    await closeEditor(tester);
  });

  testWidgets('checkboxes can be shown on a text note and hidden again', (
    tester,
  ) async {
    tallScreen(tester);
    final id = (await tester.runAsync(
      () => NoteRepository(
        db.noteDao,
      ).create(title: 'Shopping', body: 'Oat milk\nEggs'),
    ))!.id;
    await pump(tester, EditorScreen(noteId: id));

    await tester.tap(find.byTooltip('More'));
    await settle(tester);
    await tester.tap(find.text('Show checkboxes'));
    await settle(tester);

    expect(find.widgetWithText(TextField, 'Oat milk'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Eggs'), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(2));

    await tester.tap(find.byTooltip('More'));
    await settle(tester);
    await tester.tap(find.text('Hide checkboxes'));
    await settle(tester);

    expect(find.byType(Checkbox), findsNothing);
    expect(
      find.widgetWithText(TextField, 'Oat milk\nEggs'),
      findsOneWidget,
    );
    await closeEditor(tester);
  });

  testWidgets('closing the editor clears out empty items', (tester) async {
    tallScreen(tester);
    final id = await createList(tester, ['Keep', '', '  ']);
    await pump(tester, EditorScreen(noteId: id));

    await tester.pumpWidget(const SizedBox());
    await settle(tester);

    expect(await itemsOf(tester, id), [('Keep', 0, false)]);
  });

  testWidgets('a list of 200 items opens and scrolls to its last item', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(411, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final id = await createList(tester, [
      for (var i = 0; i < 200; i++) 'Item $i',
    ]);
    await pump(tester, EditorScreen(noteId: id));

    await tester.scrollUntilVisible(
      find.widgetWithText(TextField, 'Item 199'),
      600,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(TextField, 'Item 199'), findsOneWidget);
    await closeEditor(tester);
  });
}
