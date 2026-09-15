import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/core/router/router.dart';
import 'package:notes/core/theme/app_theme.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/db/note_dao.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/data/repository/label_repository.dart';
import 'package:notes/data/seed.dart';

/// Labels as people use them: made from a note, browsed from the drawer,
/// tidied on the labels page, and put on several notes at once.
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

  Future<void> pumpApp(WidgetTester tester, {String at = '/'}) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // The grid seeds the starter notes and labels on its first build; a test
    // that starts on another page needs them written up front.
    await tester.runAsync(() => seedIfEmpty(db.noteDao));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: buildRouter(initialLocation: at),
        ),
      ),
    );
    await settle(tester);
  }

  /// Unmounts everything while the database is still open, so an editor's
  /// save on close lands before the tear-down closes it.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 3; i++) {
      await settle(tester);
    }
  }

  Future<List<String>> labelNames(WidgetTester tester) async => [
    for (final label in (await tester.runAsync(
      () => LabelRepository(db.noteDao).all(),
    ))!)
      label.name,
  ];

  Future<List<String>> labelsOn(WidgetTester tester, String title) async {
    final notes = (await tester.runAsync(
      () => db.noteDao.loadShelf(Shelf.active),
    ))!;
    return [
      for (final label in notes.firstWhere((n) => n.title == title).labels)
        label.name,
    ];
  }

  Finder inDrawer(String text) =>
      find.descendant(of: find.byType(Drawer), matching: find.text(text));

  testWidgets('a label made from a note shows on it and in the drawer', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Bike'));
    await settle(tester);
    await tester.tap(find.byTooltip('More'));
    await settle(tester);
    await tester.tap(find.text('Labels'));
    await settle(tester);

    expect(find.text('LABELS ON THIS NOTE'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Garage');
    await settle(tester);
    await tester.tap(find.text('Create “Garage”'));
    await settle(tester);
    expect(
      tester
          .widget<Checkbox>(
            find.descendant(
              of: find.widgetWithText(InkWell, 'Garage'),
              matching: find.byType(Checkbox),
            ),
          )
          .value,
      isTrue,
    );

    await tester.tap(find.byTooltip('Back'));
    await settle(tester);
    expect(find.text('Garage'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await settle(tester);
    expect(await labelsOn(tester, 'Bike'), ['Garage']);

    await tester.tap(find.byTooltip('Open menu'));
    await settle(tester);
    expect(inDrawer('Garage'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a label page holds its notes, and notes written there wear it', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip('Open menu'));
    await settle(tester);
    await tester.tap(inDrawer('Reading'));
    await settle(tester);

    expect(find.text('2 NOTES'), findsOneWidget);
    expect(find.text('The Peregrine — J.A. Baker'), findsOneWidget);
    expect(find.text('Bike'), findsNothing);

    await tester.tap(find.text('Take a note'));
    await settle(tester);
    // The label is on the page before anything is written.
    expect(find.text('Reading'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Pilgrim at Tinker');
    await settle(tester);
    await tester.tap(find.byTooltip('Back'));
    await settle(tester);

    expect(find.text('3 NOTES'), findsOneWidget);
    expect(await labelsOn(tester, 'Pilgrim at Tinker'), ['Reading']);
    await unmount(tester);
  });

  testWidgets('backing out of a blank note on a label page leaves nothing', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Open menu'));
    await settle(tester);
    await tester.tap(inDrawer('Reading'));
    await settle(tester);

    await tester.tap(find.text('Take a note'));
    await settle(tester);
    await tester.tap(find.byTooltip('Back'));
    await settle(tester);

    expect(find.text('2 NOTES'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('labels are renamed, refused a taken name, and reordered', (
    tester,
  ) async {
    await pumpApp(tester, at: '/labels');

    await tester.enterText(find.widgetWithText(TextField, 'Admin'), 'Papers');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(await labelNames(tester), ['Home', 'Papers', 'Reading']);

    await tester.enterText(find.widgetWithText(TextField, 'Reading'), 'home');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(find.text('“home” is already a label'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Reading'), findsOneWidget);
    expect(await labelNames(tester), ['Home', 'Papers', 'Reading']);

    final handle = tester.ensureSemantics();
    final first = tester.getSemantics(
      find.ancestor(
        of: find.widgetWithText(TextField, 'Home'),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && (w.properties.customSemanticsActions != null),
        ),
      ).first,
    );
    first.owner!.performAction(
      first.id,
      SemanticsAction.customAction,
      CustomSemanticsAction.getIdentifier(
        const CustomSemanticsAction(label: 'Move down'),
      ),
    );
    await settle(tester);
    handle.dispose();
    expect(await labelNames(tester), ['Papers', 'Home', 'Reading']);

    await tester.enterText(find.widgetWithText(TextField, 'New label'), 'Trip');
    await settle(tester);
    await tester.tap(find.byTooltip('Create label'));
    await settle(tester);
    expect(await labelNames(tester), ['Papers', 'Home', 'Reading', 'Trip']);
    await unmount(tester);
  });

  testWidgets('a deleted label comes off its notes, and undo puts it back', (
    tester,
  ) async {
    await pumpApp(tester, at: '/labels');

    await tester.tap(find.byTooltip('Delete “Admin”'));
    await settle(tester);
    expect(await labelNames(tester), ['Home', 'Reading']);
    expect(await labelsOn(tester, 'Dentist'), isEmpty);

    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(await labelNames(tester), ['Home', 'Admin', 'Reading']);
    expect(await labelsOn(tester, 'Dentist'), ['Admin']);
    await unmount(tester);
  });

  testWidgets('deleting the label a page shows returns there to the grid', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Open menu'));
    await settle(tester);
    await tester.tap(inDrawer('Admin'));
    await settle(tester);
    expect(find.text('Dentist'), findsOneWidget);

    await tester.tap(find.byTooltip('Open menu'));
    await settle(tester);
    await tester.tap(find.text('Edit labels'));
    await settle(tester);
    await tester.tap(find.byTooltip('Delete “Admin”'));
    await settle(tester);
    // Still on the labels page, with undo on offer.
    expect(find.text('Label deleted'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await settle(tester);
    expect(find.text('8 NOTES'), findsOneWidget);
    expect(find.text('Bike'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('selected notes get a label together', (tester) async {
    await pumpApp(tester);

    await tester.longPress(find.text('Bike'));
    await tester.pump();
    await tester.tap(find.text('Dentist'));
    await tester.pump();
    await tester.tap(find.byTooltip('Labels'));
    await settle(tester);

    expect(find.text('LABELS ON 2 NOTES'), findsOneWidget);
    await tester.tap(find.text('Home'));
    await settle(tester);
    await tester.tap(find.byTooltip('Back'));
    await settle(tester);

    expect(find.byTooltip('Clear selection'), findsNothing);
    expect(await labelsOn(tester, 'Bike'), ['Home']);
    expect(await labelsOn(tester, 'Dentist'), ['Home', 'Admin']);
    await unmount(tester);
  });
}
