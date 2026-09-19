import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/core/router/router.dart';
import 'package:notes/core/theme/app_theme.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/db/note_dao.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/data/repository/note_repository.dart';
import 'package:notes/data/seed.dart';
import 'package:notes/domain/model/note.dart';

import '../support/fake_document_picker.dart';
import '../support/fake_home_widgets.dart';
import '../support/fake_image_processor.dart';
import '../support/fake_phone_system.dart';
import '../support/fake_photo_source.dart';
import '../support/fake_reminder_scheduler.dart';

/// Opens something over a page: a note, a sheet, the drawer.
typedef Step = Future<void> Function(WidgetTester tester);

/// The finish gate of §10, surface by surface, in both themes on a 360dp
/// phone: touch targets of at least 48dp, a label on everything tappable, text
/// at 4.5:1 against what it is drawn on, and at 200% text nothing clipped or
/// overflowing.
void main() {
  late AppDatabase db;
  late Directory media;
  late Directory cache;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    media = Directory.systemTemp.createTempSync('notes_gate_media_');
    cache = Directory.systemTemp.createTempSync('notes_gate_cache_');
  });

  tearDown(() async {
    await db.close();
    media.deleteSync(recursive: true);
    cache.deleteSync(recursive: true);
  });

  List<Override> overrides() => [
    appDatabaseProvider.overrideWithValue(db),
    mediaRootProvider.overrideWith((ref) async => media),
    cacheRootProvider.overrideWith((ref) async => cache),
    documentPickerProvider.overrideWithValue(FakeDocumentPicker()),
    imageProcessorProvider.overrideWithValue(FakeImageProcessor()),
    photoSourceProvider.overrideWithValue(FakePhotoSource()),
    reminderSchedulerProvider.overrideWithValue(FakeReminderScheduler()),
    phoneSystemProvider.overrideWithValue(FakePhoneSystem(maker: 'Xiaomi')),
    homeWidgetsProvider.overrideWithValue(FakeHomeWidgets()),
  ];

  Future<void> settle(WidgetTester tester, {int turns = 8}) async {
    for (var i = 0; i < turns; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// The starter notes, with one archived, one in the trash, and a note long
  /// enough to test the limits: a long title and a 5,000-character body.
  Future<void> fill(WidgetTester tester) async {
    await tester.runAsync(() async {
      await seedIfEmpty(db.noteDao);
      final notes = NoteRepository(db.noteDao);
      final all = await db.noteDao.loadShelf(Shelf.active);
      Note titled(String title) => all.firstWhere((n) => n.title == title);
      await notes.setArchived(titled('Dentist').id, archived: true);
      await notes.delete(titled('Bike').id);
      await notes.create(
        title:
            'A title long enough to run past three lines on a narrow card '
            'and keep going well past where anyone would stop typing one',
        body: List.filled(500, 'Ten chars.').join(),
      );
    });
  }

  Future<void> pumpAt(
    WidgetTester tester,
    String location, {
    required bool dark,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await fill(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp.router(
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          routerConfig: buildRouter(initialLocation: location),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester, turns: 12);
  }

  /// Scrolls the page until [text] is on screen. The grid builds its cards
  /// as they come into view, so one pushed down by the long note, or by
  /// large text, is not there to find until then.
  Future<void> reveal(WidgetTester tester, String text) async {
    await tester.scrollUntilVisible(
      find.text(text),
      200,
      scrollable: find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .first,
    );
    // At 200% text a row can stop half past the edge.
    await tester.ensureVisible(find.text(text).first);
    await settle(tester, turns: 2);
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await reveal(tester, text);
    await tester.tap(find.text(text).first);
    await settle(tester);
  }

  Future<void> tapTooltip(WidgetTester tester, String tooltip) async {
    await tester.tap(find.byTooltip(tooltip).first);
    await settle(tester);
  }

  final surfaces = <String, (String, Step?)>{
    'the grid': ('/', null),
    'the drawer': ('/', (t) => tapTooltip(t, 'Open menu')),
    'selection mode': (
      '/',
      (t) async {
        await reveal(t, 'Groceries');
        await t.longPress(find.text('Groceries'));
        await settle(t);
      },
    ),
    'a text note': ('/', (t) => tapText(t, 'Renew passport')),
    'a list': ('/', (t) => tapText(t, 'Groceries')),
    'the colour sheet': (
      '/',
      (t) async {
        await tapText(t, 'Renew passport');
        await tapTooltip(t, 'Colour');
      },
    ),
    'the reminder sheet': (
      '/',
      (t) async {
        await tapText(t, 'Renew passport');
        await tapTooltip(t, 'Reminder');
      },
    ),
    'the label picker': (
      '/',
      (t) async {
        await tapText(t, 'Renew passport');
        await tapTooltip(t, 'More');
        await tapText(t, 'Labels');
      },
    ),
    'a label page': ('/', null),
    'the archive': ('/archive', null),
    'the trash': ('/trash', null),
    'a note in the trash': ('/trash', (t) => tapText(t, 'Bike')),
    'reminders': ('/reminders', null),
    'search': (
      '/search',
      (t) async {
        await t.enterText(find.byType(TextField), 'the');
        await settle(t);
      },
    ),
    'labels': ('/labels', null),
    'settings': ('/settings', null),
    'the widget sheet': (
      '/settings',
      (t) => tapText(t, 'Add the notes widget'),
    ),
    'the export sheet': (
      '/settings',
      (t) async {
        await reveal(t, 'Export notes');
        await t.tap(find.text('Export notes'));
        for (var i = 0; i < 100 && find.text('Share').evaluate().isEmpty; i++) {
          await settle(t, turns: 1);
        }
        await settle(t);
      },
    ),
  };

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';
    for (final MapEntry(key: name, value: (location, open))
        in surfaces.entries) {
      Future<void> show(WidgetTester tester, {double textScale = 1}) async {
        var at = location;
        if (name == 'a label page') {
          await tester.runAsync(() => seedIfEmpty(db.noteDao));
          final labels = (await tester.runAsync(db.noteDao.allLabels))!;
          at = '/label/${labels.first.id}';
        }
        await pumpAt(tester, at, dark: dark, textScale: textScale);
        await open?.call(tester);
      }

      group('$name, $theme', () {
        // Each test takes the app down even when it fails, so the database
        // closes after the streams reading it and the next test starts clean.
        testWidgets('touch targets are 48dp and labelled', (tester) async {
          final handle = tester.ensureSemantics();
          try {
            await show(tester);

            await expectLater(
              tester,
              meetsGuideline(androidTapTargetGuideline),
            );
            await expectLater(
              tester,
              meetsGuideline(labeledTapTargetGuideline),
            );
          } finally {
            handle.dispose();
            await unmount(tester);
          }
        });

        testWidgets('text reads at 4.5:1', (tester) async {
          final handle = tester.ensureSemantics();
          try {
            await show(tester);

            await expectLater(tester, meetsGuideline(textContrastGuideline));
          } finally {
            handle.dispose();
            await unmount(tester);
          }
        });

        // An overflow or a clipped layout is reported by the framework itself,
        // with the widget that caused it, and fails the test.
        testWidgets('holds together at 200% text', (tester) async {
          try {
            await show(tester, textScale: 2);
          } finally {
            await unmount(tester);
          }
        });
      });
    }
  }

  testWidgets('a 5,000-character body opens whole in the editor', (
    tester,
  ) async {
    await pumpAt(tester, '/', dark: false);
    await tester.scrollUntilVisible(
      find.textContaining('A title long enough'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tapText(
      tester,
      'A title long enough to run past three lines on a '
      'narrow card and keep going well past where anyone would stop typing '
      'one',
    );

    final bodies = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((field) => field.controller?.text ?? '');
    expect(bodies, contains(hasLength(5000)));
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  test('the long note is stored whole', () async {
    final notes = NoteRepository(db.noteDao);
    final note = await notes.create(
      body: List.filled(500, 'Ten chars.').join(),
    );
    await db.noteDao.updateNote(
      note.id,
      const NotesCompanion(pinned: Value(true)),
    );
    expect((await notes.load(note.id))!.body, hasLength(5000));
  });
}
