import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/app.dart';
import 'package:notes/core/router/router.dart';
import 'package:notes/core/theme/app_theme.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/db/note_dao.dart';
import 'package:notes/data/device/home_widgets.dart';
import 'package:notes/data/home_widgets/home_widget_sync.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/data/repository/checklist_repository.dart';
import 'package:notes/data/repository/label_repository.dart';
import 'package:notes/data/repository/note_repository.dart';
import 'package:notes/data/repository/reminder_repository.dart';
import 'package:notes/data/repository/settings_repository.dart';
import 'package:notes/data/seed.dart';
import 'package:notes/domain/model/label.dart';
import 'package:notes/domain/model/note.dart';
import 'package:notes/domain/model/settings.dart';
import 'package:notes/features/editor/editor_screen.dart';
import 'package:notes/features/notes/notes_screen.dart';

import '../support/fake_document_picker.dart';
import '../support/fake_home_widgets.dart';
import '../support/fake_image_processor.dart';
import '../support/fake_phone_system.dart';
import '../support/fake_photo_source.dart';
import '../support/fake_reminder_scheduler.dart';

/// The home screen widgets: what they are handed as notes change, what a tap
/// on them opens, and placing them from settings.
void main() {
  late AppDatabase db;
  late Directory media;
  late Directory picked;
  late FakeHomeWidgets widgets;
  late FakePhotoSource photos;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    media = Directory.systemTemp.createTempSync('notes_widget_media_');
    picked = Directory.systemTemp.createTempSync('notes_widget_picked_');
    widgets = FakeHomeWidgets();
    photos = FakePhotoSource();
  });

  tearDown(() async {
    await db.close();
    media.deleteSync(recursive: true);
    picked.deleteSync(recursive: true);
  });

  List<Override> overrides() => [
    appDatabaseProvider.overrideWithValue(db),
    mediaRootProvider.overrideWith((ref) async => media),
    cacheRootProvider.overrideWith((ref) async => media),
    documentPickerProvider.overrideWithValue(FakeDocumentPicker()),
    imageProcessorProvider.overrideWithValue(FakeImageProcessor()),
    photoSourceProvider.overrideWithValue(photos),
    reminderSchedulerProvider.overrideWithValue(FakeReminderScheduler()),
    phoneSystemProvider.overrideWithValue(FakePhoneSystem()),
    homeWidgetsProvider.overrideWithValue(widgets),
  ];

  Future<void> settle(WidgetTester tester, {int turns = 10}) async {
    for (var i = 0; i < turns; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  void phoneScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpApp(WidgetTester tester) async {
    phoneScreen(tester);
    await tester.runAsync(() => seedIfEmpty(db.noteDao));
    await tester.pumpWidget(
      ProviderScope(overrides: overrides(), child: const NotesApp()),
    );
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester, turns: 20);
  }

  Future<Note> noteTitled(WidgetTester tester, String title) async =>
      (await tester.runAsync(
        () async =>
            (await db.noteDao.loadShelf(Shelf.active))
                .firstWhere((note) => note.title == title),
      ))!;

  Map<String, Object?> feedIn(Map<String, Object?> snapshot, String key) => [
    for (final feed in snapshot['feeds']! as List) feed as Map<String, Object?>,
  ].firstWhere((feed) => feed['feed'] == key);

  /// The titles a widget set to [feed] shows, in order.
  Future<Label> labelNamed(String name) async => (await LabelRepository(
    db.noteDao,
  ).all()).firstWhere((label) => label.name == name);

  List<String> titlesIn(Map<String, Object?> snapshot, {String feed = 'all'}) {
    final notes = snapshot['notes']! as Map<String, Object?>;
    return [
      for (final id in feedIn(snapshot, feed)['notes']! as List)
        (notes[id]! as Map<String, Object?>)['title']! as String,
    ];
  }

  group('what the widget is handed', () {
    late HomeWidgetSync sync;

    setUp(() async {
      await seedIfEmpty(db.noteDao);
      sync = HomeWidgetSync(
        NoteRepository(db.noteDao),
        SettingsRepository(db.preferenceDao),
        widgets,
      )..start();
    });

    tearDown(() => sync.dispose());

    Future<void> landed() async {
      // The stream reads on its own schedule; give it a moment, then wait
      // for the hand-over it started.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sync.idle;
    }

    test('the notes as the grid shows them, as soon as it starts', () async {
      await landed();

      final snapshot = widgets.published.single;
      final seeded = await db.noteDao.loadShelf(Shelf.active);
      expect(feedIn(snapshot, 'all')['count'], seeded.length);
      expect(titlesIn(snapshot).first, 'Flat viewing — Aurel Vlaicu 12');
    });

    test('the pinned notes and each label, for widgets set to them', () async {
      await landed();

      final snapshot = widgets.published.single;
      final seeded = await db.noteDao.loadShelf(Shelf.active);
      final admin = await labelNamed('Admin');
      expect(titlesIn(snapshot, feed: 'pinned'), [
        for (final note in seeded.where((note) => note.pinned)) note.title,
      ]);
      expect(feedIn(snapshot, 'label:${admin.id}')['title'], 'Admin');
      expect(titlesIn(snapshot, feed: 'label:${admin.id}'), [
        for (final note in seeded.where(
          (note) => note.labels.any((label) => label.id == admin.id),
        ))
          note.title,
      ]);
    });

    test('a note pinned joins the pinned widget', () async {
      await landed();
      final bike = (await db.noteDao.loadShelf(Shelf.active))
          .firstWhere((note) => note.title == 'Bike');

      await NoteRepository(db.noteDao).setPinned(bike.id, pinned: true);
      await landed();

      expect(
        titlesIn(widgets.published.first, feed: 'pinned'),
        isNot(contains('Bike')),
      );
      expect(
        titlesIn(widgets.published.last, feed: 'pinned'),
        contains('Bike'),
      );
    });

    test('a label renamed or deleted changes its feed', () async {
      await landed();
      final labels = LabelRepository(db.noteDao);
      final admin = await labelNamed('Admin');

      await labels.rename(admin.id, 'Paperwork');
      await landed();
      expect(
        feedIn(widgets.published.last, 'label:${admin.id}')['title'],
        'Paperwork',
      );

      await labels.delete(admin.id);
      await landed();
      final feeds = [
        for (final feed in widgets.published.last['feeds']! as List)
          (feed as Map<String, Object?>)['feed'],
      ];
      expect(feeds, isNot(contains('label:${admin.id}')));
    });

    test('a note archived leaves the widget', () async {
      await landed();
      final bike = (await db.noteDao.loadShelf(Shelf.active))
          .firstWhere((note) => note.title == 'Bike');

      await NoteRepository(db.noteDao).setArchived(bike.id, archived: true);
      await landed();

      expect(widgets.published, hasLength(2));
      expect(titlesIn(widgets.published.first), contains('Bike'));
      expect(titlesIn(widgets.published.last), isNot(contains('Bike')));
      expect(
        feedIn(widgets.published.last, 'all')['count'],
        (feedIn(widgets.published.first, 'all')['count']! as int) - 1,
      );
    });

    test('a change the widget does not show sends nothing new', () async {
      await landed();
      final bike = (await db.noteDao.loadShelf(Shelf.active))
          .firstWhere((note) => note.title == 'Bike');

      await ReminderRepository(db.noteDao)
          .set(bike.id, DateTime.now().add(const Duration(days: 1)));
      await landed();

      expect(widgets.published, hasLength(1));
    });

    Map<String, Object?> pagesIn(Map<String, Object?> snapshot) =>
        snapshot['pages']! as Map<String, Object?>;

    test('the notes a note widget can be set to', () async {
      await landed();

      final snapshot = widgets.published.single;
      final seeded = await db.noteDao.loadShelf(Shelf.active);
      expect(
        [
          for (final choice in snapshot['choices']! as List)
            (choice as Map)['id'],
        ],
        [for (final note in seeded) note.id],
      );
      expect(pagesIn(snapshot), isEmpty);
    });

    test('a note widget placed carries its note whole', () async {
      await landed();
      final groceries = (await db.noteDao.loadShelf(Shelf.active))
          .firstWhere((note) => note.title == 'Groceries');

      widgets.show({groceries.id});
      await landed();

      final page =
          pagesIn(widgets.published.last)[groceries.id]!
              as Map<String, Object?>;
      expect(page['title'], 'Groceries');
      expect(
        (page['items']! as List).length + (page['done']! as List).length,
        groceries.items.where((item) => item.text.trim().isNotEmpty).length,
      );

      // Removed, the widget's note is no longer carried.
      widgets.show(const {});
      await landed();
      expect(pagesIn(widgets.published.last), isEmpty);
    });

    test('an item ticked in the app ticks on the note widget', () async {
      final groceries = (await db.noteDao.loadShelf(Shelf.active))
          .firstWhere((note) => note.title == 'Groceries');
      final open = groceries.uncheckedItems.first;
      widgets.show({groceries.id});
      await landed();

      await ChecklistRepository(db.noteDao)
          .setChecked(groceries.id, open.id, checked: true);
      await landed();

      final page =
          pagesIn(widgets.published.last)[groceries.id]!
              as Map<String, Object?>;
      expect([
        for (final item in page['done']! as List) (item as Map)['id'],
      ], contains(open.id));
    });

    test('the checked items fold as the setting has them', () async {
      final groceries = (await db.noteDao.loadShelf(Shelf.active))
          .firstWhere((note) => note.title == 'Groceries');
      widgets.show({groceries.id});
      await landed();
      Map<String, Object?> page() =>
          pagesIn(widgets.published.last)[groceries.id]!
              as Map<String, Object?>;
      expect(page()['folded'], isTrue);

      await SettingsRepository(db.preferenceDao)
          .setCheckedItems(CheckedItems.shown);
      await landed();

      expect(page()['folded'], isFalse);
    });
  });

  group('a tap on a widget', () {
    testWidgets('that started the app opens its note', (tester) async {
      await tester.runAsync(() => seedIfEmpty(db.noteDao));
      final groceries = await noteTitled(tester, 'Groceries');
      widgets.launchAction = OpenNote(groceries.id);

      await pumpApp(tester);

      expect(find.byType(EditorScreen), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Groceries'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('while the app runs starts a list', (tester) async {
      await pumpApp(tester);
      expect(find.byType(EditorScreen), findsNothing);

      widgets.tap(const NewList());
      await settle(tester);

      expect(find.byType(EditorScreen), findsOneWidget);
      expect(find.text('List item'), findsWidgets);
      await unmount(tester);
    });

    testWidgets('on add photos opens a note once photos are chosen', (
      tester,
    ) async {
      await pumpApp(tester);

      // Closing the picker leaves the app where it was.
      widgets.tap(const AddPhotos());
      await settle(tester);
      expect(photos.pickCalls, 1);
      expect(find.byType(EditorScreen), findsNothing);

      photos.picks = [
        File('${picked.path}/front.jpg')..writeAsBytesSync(List.filled(64, 7)),
      ];
      widgets.tap(const AddPhotos());
      await settle(tester, turns: 20);

      expect(find.byType(EditorScreen), findsOneWidget);
      expect(find.bySemanticsLabel('Image 1 of 1'), findsOneWidget);
      await unmount(tester);
    });

    /// Types [title] into the note open in the editor and closes it.
    Future<Note> write(WidgetTester tester, String title) async {
      await tester.enterText(find.byType(TextField).first, title);
      await settle(tester);
      await tester.tap(find.byTooltip('Back'));
      await settle(tester);
      return noteTitled(tester, title);
    }

    testWidgets('on + of a label widget starts a note wearing it', (
      tester,
    ) async {
      await pumpApp(tester);
      final admin = (await tester.runAsync(() => labelNamed('Admin')))!;

      widgets.tap(NewNote(feed: LabelFeed(admin.id)));
      await settle(tester);
      expect(
        find.descendant(
          of: find.byType(EditorScreen),
          matching: find.text('Admin'),
        ),
        findsOneWidget,
      );
      final note = await write(tester, 'Tax return');

      expect([for (final label in note.labels) label.name], ['Admin']);
      expect(note.pinned, isFalse);
      await unmount(tester);
    });

    testWidgets('on + of the pinned widget starts a pinned note', (
      tester,
    ) async {
      await pumpApp(tester);

      widgets.tap(const NewNote(feed: PinnedFeed()));
      await settle(tester);
      expect(find.byTooltip('Unpin'), findsOneWidget);
      final note = await write(tester, 'Door code');

      expect(note.pinned, isTrue);
      expect(note.labels, isEmpty);
      await unmount(tester);
    });

    testWidgets('on + of a widget whose label is gone starts a plain note', (
      tester,
    ) async {
      await pumpApp(tester);

      widgets.tap(const NewNote(feed: LabelFeed('gone')));
      await settle(tester);
      final note = await write(tester, 'Loose thought');

      expect(note.labels, isEmpty);
      await unmount(tester);
    });

    testWidgets('on the heading of a label widget shows its page', (
      tester,
    ) async {
      addTearDown(() => appRouter.go('/'));
      await tester.runAsync(() => seedIfEmpty(db.noteDao));
      final groceries = await noteTitled(tester, 'Groceries');
      final admin = (await tester.runAsync(() => labelNamed('Admin')))!;
      // A note left open in the editor closes for the label's page.
      widgets.launchAction = OpenNote(groceries.id);
      await pumpApp(tester);
      expect(find.byType(EditorScreen), findsOneWidget);

      widgets.tap(ShowFeed(LabelFeed(admin.id)));
      await settle(tester);

      expect(find.byType(EditorScreen), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is NotesScreen && widget.labelId == admin.id,
        ),
        findsOneWidget,
      );
      await unmount(tester);
    });

    testWidgets(
      'on the heading of the pinned widget leaves the app as it was',
      (tester) async {
        await tester.runAsync(() => seedIfEmpty(db.noteDao));
        final groceries = await noteTitled(tester, 'Groceries');
        widgets.launchAction = OpenNote(groceries.id);
        await pumpApp(tester);

        widgets.tap(const ShowFeed(PinnedFeed()));
        await settle(tester);

        expect(find.byType(EditorScreen), findsOneWidget);
        await unmount(tester);
      },
    );

    testWidgets('on + of a note widget opens its list on a new item', (
      tester,
    ) async {
      await tester.runAsync(() => seedIfEmpty(db.noteDao));
      final groceries = await noteTitled(tester, 'Groceries');
      final before = groceries.items.length;
      await pumpApp(tester);

      widgets.tap(AddItem(groceries.id));
      await settle(tester);

      expect(find.byType(EditorScreen), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Groceries'), findsOneWidget);
      final after = await noteTitled(tester, 'Groceries');
      expect(after.items, hasLength(before + 1));
      // The new item is the last of the open ones, empty and being typed
      // into.
      final added = after.uncheckedItems.last;
      expect(added.text, '');
      final focused = tester.widget<EditableText>(
        find.byWidgetPredicate(
          (widget) => widget is EditableText && widget.focusNode.hasFocus,
        ),
      );
      expect(focused.controller.text, '');

      // Left empty, it goes as the note closes.
      await tester.tap(find.byTooltip('Back'));
      await settle(tester);
      expect((await noteTitled(tester, 'Groceries')).items, hasLength(before));
      await unmount(tester);
    });

    testWidgets('on + of a note widget whose note is text just opens it', (
      tester,
    ) async {
      await tester.runAsync(() => seedIfEmpty(db.noteDao));
      final flat = await noteTitled(tester, 'Flat viewing — Aurel Vlaicu 12');
      await pumpApp(tester);

      widgets.tap(AddItem(flat.id));
      await settle(tester);

      expect(find.byType(EditorScreen), findsOneWidget);
      expect((await noteTitled(tester, flat.title)).items, isEmpty);
      await unmount(tester);
    });

    testWidgets('on a note deleted since says so', (tester) async {
      widgets.launchAction = const OpenNote('gone');

      await pumpApp(tester);

      expect(find.byType(EditorScreen), findsNothing);
      expect(find.text('That note has been deleted'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('an action as Android sends it', () {
    test('a note for the feed the widget shows', () {
      expect(
        WidgetAction.decode({'action': 'newNote', 'feed': 'label:abc'}),
        const NewNote(feed: LabelFeed('abc')),
      );
      expect(
        WidgetAction.decode({'action': 'newNote', 'feed': 'pinned'}),
        const NewNote(feed: PinnedFeed()),
      );
      // The new note widget, and a widget whose label is gone, send none.
      expect(WidgetAction.decode({'action': 'newNote'}), const NewNote());
    });

    test('a new item on the list a note widget shows', () {
      expect(
        WidgetAction.decode({'action': 'addItem', 'noteId': 'abc'}),
        const AddItem('abc'),
      );
      expect(WidgetAction.decode({'action': 'addItem'}), isNull);
    });

    test('the page a widget mirrors, when the feed is one it knows', () {
      expect(
        WidgetAction.decode({'action': 'showFeed', 'feed': 'label:abc'}),
        const ShowFeed(LabelFeed('abc')),
      );
      expect(
        WidgetAction.decode({'action': 'showFeed', 'feed': 'all'}),
        const ShowFeed(AllFeed()),
      );
      expect(WidgetAction.decode({'action': 'showFeed'}), isNull);
      expect(
        WidgetAction.decode({'action': 'showFeed', 'feed': 'label:'}),
        isNull,
      );
      expect(
        WidgetAction.decode({'action': 'showFeed', 'feed': 'recent'}),
        isNull,
      );
    });
  });

  group("a note's menu", () {
    Future<void> openMenu(WidgetTester tester, String title) async {
      await tester.runAsync(() => seedIfEmpty(db.noteDao));
      widgets.launchAction = OpenNote((await noteTitled(tester, title)).id);
      await pumpApp(tester);
      await tester.tap(find.byTooltip('More'));
      // Long enough for the menu to finish opening.
      await settle(tester, turns: 5);
    }

    testWidgets('puts the note on the home screen', (tester) async {
      await openMenu(tester, 'Groceries');

      await tester.ensureVisible(find.text('Add to home screen'));
      await settle(tester, turns: 2);
      await tester.tap(find.text('Add to home screen'));
      await settle(tester);

      final groceries = await noteTitled(tester, 'Groceries');
      expect(widgets.pinnedNotes, [groceries.id]);
      await unmount(tester);
    });

    testWidgets('offers it only where the launcher can place it', (
      tester,
    ) async {
      widgets.pinnable = false;
      await openMenu(tester, 'Groceries');

      expect(find.text('Make a copy'), findsOneWidget);
      expect(find.text('Add to home screen'), findsNothing);
      await unmount(tester);
    });
  });

  group('settings', () {
    Future<void> pumpSettings(WidgetTester tester) async {
      phoneScreen(tester);
      await tester.runAsync(() => seedIfEmpty(db.noteDao));
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: buildRouter(initialLocation: '/settings'),
          ),
        ),
      );
      await settle(tester);
    }

    Future<void> tapAction(WidgetTester tester, String label) async {
      await tester.scrollUntilVisible(
        find.text(label),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text(label));
      // Long enough for a sheet to finish rising.
      await settle(tester, turns: 5);
    }

    testWidgets('places either widget on the home screen', (tester) async {
      await pumpSettings(tester);

      await tapAction(tester, 'Add the notes widget');
      await tester.tap(find.text('All notes'));
      await settle(tester, turns: 2);
      await tapAction(tester, 'Add the new note widget');

      expect(widgets.pinned, [
        (HomeWidget.notes, const AllFeed()),
        (HomeWidget.capture, const AllFeed()),
      ]);
      await unmount(tester);
    });

    testWidgets('asks what the notes widget shows before placing it', (
      tester,
    ) async {
      await pumpSettings(tester);
      final admin = await tester.runAsync(() => labelNamed('Admin'));

      // Dismissed, the sheet places nothing.
      await tapAction(tester, 'Add the notes widget');
      expect(find.text('SHOW ON THIS WIDGET'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await settle(tester, turns: 4);
      expect(widgets.pinned, isEmpty);

      await tapAction(tester, 'Add the notes widget');
      await tester.tap(find.text('Pinned notes'));
      await settle(tester, turns: 4);
      await tapAction(tester, 'Add the notes widget');
      await tester.scrollUntilVisible(
        find.text('Admin'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Admin'));
      await settle(tester, turns: 4);

      expect(widgets.pinned, [
        (HomeWidget.notes, const PinnedFeed()),
        (HomeWidget.notes, LabelFeed(admin!.id)),
      ]);
      await unmount(tester);
    });

    testWidgets('offers nothing where the launcher cannot place them', (
      tester,
    ) async {
      widgets.pinnable = false;
      await pumpSettings(tester);

      await tester.scrollUntilVisible(
        find.text('Rebuild search index'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('HOME SCREEN'), findsNothing);
      expect(find.text('Add the notes widget'), findsNothing);
      await unmount(tester);
    });
  });
}
