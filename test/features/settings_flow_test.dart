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
import 'package:notes/data/providers.dart';
import 'package:notes/data/repository/checklist_repository.dart';
import 'package:notes/data/repository/note_repository.dart';
import 'package:notes/data/repository/settings_repository.dart';
import 'package:notes/data/seed.dart';
import 'package:notes/domain/model/note_type.dart';
import 'package:notes/domain/model/settings.dart';
import 'package:notes/features/editor/editor_screen.dart';
import 'package:notes/features/shelf/shelf_screen.dart';

import '../support/fake_document_picker.dart';
import '../support/fake_home_widgets.dart';
import '../support/fake_image_processor.dart';
import '../support/fake_phone_system.dart';
import '../support/fake_photo_source.dart';
import '../support/fake_reminder_scheduler.dart';

/// Settings as people change them, and notes leaving the phone and coming
/// back.
void main() {
  late AppDatabase db;
  late Directory media;
  late Directory cache;
  late FakeDocumentPicker picker;
  late FakePhoneSystem phone;
  late FakeHomeWidgets homeWidgets;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    media = Directory.systemTemp.createTempSync('notes_settings_media_');
    cache = Directory.systemTemp.createTempSync('notes_settings_cache_');
    picker = FakeDocumentPicker();
    phone = FakePhoneSystem();
    homeWidgets = FakeHomeWidgets();
  });

  tearDown(() async {
    await db.close();
    media.deleteSync(recursive: true);
    cache.deleteSync(recursive: true);
  });

  SettingsRepository settings() => SettingsRepository(db.preferenceDao);

  List<Override> overrides() => [
    appDatabaseProvider.overrideWithValue(db),
    mediaRootProvider.overrideWith((ref) async => media),
    cacheRootProvider.overrideWith((ref) async => cache),
    documentPickerProvider.overrideWithValue(picker),
    imageProcessorProvider.overrideWithValue(FakeImageProcessor()),
    photoSourceProvider.overrideWithValue(FakePhotoSource()),
    reminderSchedulerProvider.overrideWithValue(FakeReminderScheduler()),
    phoneSystemProvider.overrideWithValue(phone),
    homeWidgetsProvider.overrideWithValue(homeWidgets),
  ];

  Future<void> settle(WidgetTester tester, {int turns = 8}) async {
    for (var i = 0; i < turns; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Pumps until [found] is on screen, then lets the sheet finish rising.
  /// Exports and imports run on isolates and real files, which only move on
  /// between pumps.
  Future<void> pumpUntilFound(WidgetTester tester, Finder found) async {
    for (var i = 0; i < 300; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 16));
      if (found.evaluate().isNotEmpty) {
        await tester.pump(const Duration(milliseconds: 400));
        return;
      }
    }
    fail('Never found $found');
  }

  void phoneScreen(WidgetTester tester, {double textScale = 1}) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Future<void> pumpRouter(
    WidgetTester tester, {
    String at = '/settings',
  }) async {
    await tester.runAsync(() => seedIfEmpty(db.noteDao));
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: buildRouter(initialLocation: at),
        ),
      ),
    );
    await settle(tester);
  }

  /// Scrolls the settings page to [label] and taps it.
  Future<void> tapSetting(WidgetTester tester, String label) async {
    await tester.scrollUntilVisible(
      find.text(label),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text(label));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text(label));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester, turns: 20);
  }

  group('theme', () {
    testWidgets('the app wears the theme picked in settings', (tester) async {
      phoneScreen(tester);
      await tester.pumpWidget(
        ProviderScope(overrides: overrides(), child: const NotesApp()),
      );
      await settle(tester);
      Brightness brightness() =>
          Theme.of(tester.element(find.byType(Scaffold).last)).brightness;
      expect(brightness(), Brightness.light);

      await tester.tap(find.byTooltip('Open menu'));
      await settle(tester);
      await tester.tap(find.text('Settings'));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Dark theme'));
      await settle(tester);

      expect(brightness(), Brightness.dark);
      // Held as the app's night mode too, for the next launch screen.
      expect(phone.nightModes.last, ThemeChoice.dark);
      expect((await tester.runAsync(settings().load))!.theme, ThemeChoice.dark);
      await unmount(tester);
    });

    testWidgets('each swatch reads as one choice of three', (tester) async {
      final handle = tester.ensureSemantics();
      phoneScreen(tester);
      await tester.runAsync(() => settings().setTheme(ThemeChoice.light));
      await pumpRouter(tester);

      expect(
        tester.getSemantics(find.bySemanticsLabel('Light theme')),
        matchesSemantics(
          label: 'Light theme',
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('System default theme')),
        matchesSemantics(
          label: 'System default theme',
          isButton: true,
          hasSelectedState: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
      await unmount(tester);
    });
  });

  group('checked items', () {
    Future<String> list(WidgetTester tester) async =>
        (await tester.runAsync(() async {
          final note = await NoteRepository(db.noteDao)
              .create(type: NoteType.checklist, title: 'Hardware');
          final lists = ChecklistRepository(db.noteDao);
          await lists.add(note.id, text: 'Hinges');
          final screws = await lists.add(note.id, text: 'Screws');
          await lists.add(note.id, text: 'Sandpaper');
          await lists.setChecked(note.id, screws.id, checked: true);
          return note.id;
        }))!;

    Future<void> pumpEditor(WidgetTester tester, String noteId) async {
      phoneScreen(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: EditorScreen(noteId: noteId),
          ),
        ),
      );
      await settle(tester);
    }

    List<String> itemsTopDown(WidgetTester tester) {
      final fields = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            {'Hinges', 'Screws', 'Sandpaper'}.contains(widget.controller?.text),
      );
      final found = fields.evaluate().toList()
        ..sort(
          (a, b) => tester
              .getTopLeft(find.byElementPredicate((e) => e == a))
              .dy
              .compareTo(
                tester.getTopLeft(find.byElementPredicate((e) => e == b)).dy,
              ),
        );
      return [
        for (final element in found)
          (element.widget as TextField).controller!.text,
      ];
    }

    testWidgets('fold away under a count by default', (tester) async {
      final id = await list(tester);
      await pumpEditor(tester, id);

      expect(find.text('1 CHECKED ITEM'), findsOneWidget);
      expect(itemsTopDown(tester), ['Hinges', 'Sandpaper']);
      await unmount(tester);
    });

    testWidgets('show at the bottom when asked', (tester) async {
      final id = await list(tester);
      await tester.runAsync(
        () => settings().setCheckedItems(CheckedItems.shown),
      );
      await pumpEditor(tester, id);

      expect(find.text('1 CHECKED ITEM'), findsOneWidget);
      expect(itemsTopDown(tester), ['Hinges', 'Sandpaper', 'Screws']);
      await unmount(tester);
    });

    testWidgets('stay in place when asked, and a new item goes last', (
      tester,
    ) async {
      final id = await list(tester);
      await tester.runAsync(
        () => settings().setCheckedItems(CheckedItems.inPlace),
      );
      await pumpEditor(tester, id);

      expect(find.text('1 CHECKED ITEM'), findsNothing);
      expect(itemsTopDown(tester), ['Hinges', 'Screws', 'Sandpaper']);

      await tester.tap(find.bySemanticsLabel('Add list item'));
      await settle(tester);
      await tester.enterText(find.byType(TextField).last, 'Glue');
      await settle(tester);
      await unmount(tester);

      final items = (await tester.runAsync(
        () => ChecklistRepository(db.noteDao).items(id),
      ))!;
      expect(
        [for (final item in items) item.text],
        ['Hinges', 'Screws', 'Sandpaper', 'Glue'],
      );
    });
  });

  testWidgets('the trash says how long its notes stay', (tester) async {
    phoneScreen(tester);
    await tester.runAsync(() async {
      final notes = NoteRepository(db.noteDao);
      await notes.delete((await notes.create(title: 'Old draft')).id);
      await settings().setTrashRetention(TrashRetention.thirtyDays);
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ShelfScreen(shelf: Shelf.trash),
        ),
      ),
    );
    await settle(tester);

    expect(find.text('NOTES HERE ARE DELETED AFTER 30 DAYS'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the empty trash says how long notes would stay', (tester) async {
    phoneScreen(tester);
    await tester.runAsync(
      () => settings().setTrashRetention(TrashRetention.oneDay),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ShelfScreen(shelf: Shelf.trash),
        ),
      ),
    );
    await settle(tester);

    expect(
      find.text('Deleted notes wait here for 1 day before they are removed.'),
      findsOneWidget,
    );
    await unmount(tester);
  });

  group('backup', () {
    testWidgets('export writes every note and hands the file to be saved', (
      tester,
    ) async {
      phoneScreen(tester);
      await pumpRouter(tester);

      await tapSetting(tester, 'Export notes');
      await pumpUntilFound(tester, find.text('Save to a file'));

      expect(find.text('8'), findsOneWidget);
      expect(find.text('notes'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('labels'), findsOneWidget);
      await tester.tap(find.text('Save to a file'));
      await settle(tester);

      expect(picker.saved, hasLength(1));
      expect(
        picker.saved.single,
        matches(RegExp(r'^notes-export-\d{8}-\d{4}\.zip$')),
      );
      expect(find.text('Export saved'), findsOneWidget);
      expect(find.text('Save to a file'), findsNothing);
      await unmount(tester);
    });

    testWidgets('closing the save picker keeps the sheet open', (tester) async {
      phoneScreen(tester);
      picker.saves = false;
      await pumpRouter(tester);

      await tapSetting(tester, 'Export notes');
      await pumpUntilFound(tester, find.text('Save to a file'));
      await tester.tap(find.text('Save to a file'));
      await settle(tester);

      expect(find.text('Save to a file'), findsOneWidget);
      expect(find.text('Export saved'), findsNothing);
      await unmount(tester);
    });

    testWidgets('replace asks for the word, then puts the export back', (
      tester,
    ) async {
      phoneScreen(tester);
      await pumpRouter(tester);
      final exported = (await tester.runAsync(() async {
        final container = ProviderScope.containerOf(
          tester.element(find.text('Settings')),
        );
        final export = await container.read(backupRepositoryProvider).export();
        final kept = File(
          '${media.parent.path}/${export.file.uri.pathSegments.last}',
        );
        await export.file.copy(kept.path);
        await NoteRepository(db.noteDao).create(title: 'Written after');
        return kept;
      }))!;
      addTearDown(exported.deleteSync);
      picker.toOpen = exported;

      await tapSetting(tester, 'Import notes');
      await pumpUntilFound(tester, find.text('8 notes in this file'));
      await tester.tap(find.text('Replace the notes here'));
      await settle(tester);
      expect(find.text('−9'), findsOneWidget);
      expect(find.text('notes here deleted'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Replace notes'));
      await settle(tester);
      final confirm = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Replace notes'),
      );
      expect(tester.widget<TextButton>(confirm).onPressed, isNull);
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Replace',
      );
      await settle(tester);
      await tester.tap(confirm);
      await pumpUntilFound(tester, find.text('Notes replaced'));

      final titles = [
        for (final note in (await tester.runAsync(
          () => db.noteDao.loadShelf(Shelf.active),
        ))!)
          note.title,
      ];
      expect(titles, hasLength(8));
      expect(titles, isNot(contains('Written after')));
      await unmount(tester);
    });

    testWidgets('merge adds only what is new', (tester) async {
      phoneScreen(tester);
      await pumpRouter(tester);
      final exported = (await tester.runAsync(() async {
        final container = ProviderScope.containerOf(
          tester.element(find.text('Settings')),
        );
        final export = await container.read(backupRepositoryProvider).export();
        final kept = File(
          '${media.parent.path}/merge-${export.file.uri.pathSegments.last}',
        );
        await export.file.copy(kept.path);
        return kept;
      }))!;
      addTearDown(exported.deleteSync);
      picker.toOpen = exported;

      await tapSetting(tester, 'Import notes');
      await pumpUntilFound(tester, find.text('8 notes in this file'));

      expect(
        find.text('Every note in this file is here already.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Import'))
            .onPressed,
        isNull,
      );
      await unmount(tester);
    });

    testWidgets('a file that is not an export says so', (tester) async {
      phoneScreen(tester);
      final text = File('${media.parent.path}/shopping.txt')
        ..writeAsStringSync('milk');
      addTearDown(text.deleteSync);
      picker.toOpen = text;
      await pumpRouter(tester);

      await tapSetting(tester, 'Import notes');
      await pumpUntilFound(
        tester,
        find.text('This file is not a Notes export'),
      );
      picker.toOpen = null;
      await tester.tap(find.text('Choose another file'));
      await settle(tester);

      expect(picker.openCalls, 2);
      expect(find.text('This file is not a Notes export'), findsNothing);
      await unmount(tester);
    });

    testWidgets('closing the open picker opens nothing', (tester) async {
      phoneScreen(tester);
      await pumpRouter(tester);

      await tapSetting(tester, 'Import notes');
      await settle(tester);

      expect(picker.openCalls, 1);
      expect(find.byType(BottomSheet), findsNothing);
      await unmount(tester);
    });
  });

  group('at 360dp and 200% text', () {
    void smallPhone(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    testWidgets('the settings page lays out whole', (tester) async {
      smallPhone(tester);
      await pumpRouter(tester);

      await tester.dragUntilVisible(
        find.textContaining('KEPT ON THIS DEVICE'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    testWidgets('the import sheet lays out whole, both ways', (tester) async {
      smallPhone(tester);
      await pumpRouter(tester);
      final exported = (await tester.runAsync(() async {
        final container = ProviderScope.containerOf(
          tester.element(find.text('Settings')),
        );
        final export = await container.read(backupRepositoryProvider).export();
        final kept = File(
          '${media.parent.path}/small-${export.file.uri.pathSegments.last}',
        );
        await export.file.copy(kept.path);
        await NoteRepository(db.noteDao).create(title: 'Only here');
        return kept;
      }))!;
      addTearDown(exported.deleteSync);
      picker.toOpen = exported;

      await tapSetting(tester, 'Import notes');
      await pumpUntilFound(tester, find.text('8 notes in this file'));
      await tester.drag(find.byType(BottomSheet), const Offset(0, -600));
      await settle(tester);
      await tester.tap(find.text('Replace the notes here'));
      await settle(tester);
      await tester.drag(find.byType(BottomSheet), const Offset(0, -600));
      await settle(tester);

      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  });
}
