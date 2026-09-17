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
import 'package:notes/data/repository/note_repository.dart';
import 'package:notes/data/repository/reminder_repository.dart';
import 'package:notes/data/seed.dart';
import 'package:notes/domain/model/note.dart';
import 'package:notes/features/editor/editor_screen.dart';

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

  List<String> titlesIn(Map<String, Object?> snapshot) => [
    for (final note in snapshot['notes']! as List)
      (note as Map<String, Object?>)['title']! as String,
  ];

  group('what the widget is handed', () {
    late HomeWidgetSync sync;

    setUp(() async {
      await seedIfEmpty(db.noteDao);
      sync = HomeWidgetSync(NoteRepository(db.noteDao), widgets)..start();
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
      expect(snapshot['count'], seeded.length);
      expect(titlesIn(snapshot).first, 'Flat viewing — Aurel Vlaicu 12');
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
        widgets.published.last['count'],
        (widgets.published.first['count']! as int) - 1,
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

    testWidgets('on a note deleted since says so', (tester) async {
      widgets.launchAction = const OpenNote('gone');

      await pumpApp(tester);

      expect(find.byType(EditorScreen), findsNothing);
      expect(find.text('That note has been deleted'), findsOneWidget);
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

    testWidgets('places either widget on the home screen', (tester) async {
      await pumpSettings(tester);

      for (final label in ['Add the notes widget', 'Add the new note widget']) {
        await tester.scrollUntilVisible(
          find.text(label),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text(label));
        await settle(tester, turns: 2);
      }

      expect(widgets.pinned, [HomeWidget.notes, HomeWidget.capture]);
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
