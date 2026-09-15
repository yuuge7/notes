import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/core/theme/app_theme.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/db/note_dao.dart';
import 'package:notes/data/media/media_store.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/data/repository/attachment_repository.dart';
import 'package:notes/domain/model/attachment.dart';
import 'package:notes/domain/model/note.dart';
import 'package:notes/domain/model/note_type.dart';
import 'package:notes/domain/model/pigment.dart';
import 'package:notes/features/images/image_mosaic.dart';
import 'package:notes/features/notes/notes_screen.dart';
import 'package:notes/features/notes/widgets/note_card.dart';

import '../support/fake_image_processor.dart';
import '../support/fake_photo_source.dart';

/// Images from the picker and the camera, through the editor, the viewer, the
/// compose bar, and the card.
void main() {
  late AppDatabase db;
  late Directory root;
  late Directory picked;
  late FakePhotoSource photos;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    root = Directory.systemTemp.createTempSync('notes_media_');
    picked = Directory.systemTemp.createTempSync('notes_picked_');
    photos = FakePhotoSource();
  });

  tearDown(() async {
    await db.close();
    root.deleteSync(recursive: true);
    picked.deleteSync(recursive: true);
  });

  File photo(String name) =>
      File('${picked.path}/$name')..writeAsBytesSync(List.filled(64, 7));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Pumps until [done] holds. Photos started from a tap go through real file
  /// writes, and those only move on between pumps.
  Future<void> pumpUntil(
    WidgetTester tester,
    Future<bool> Function() done,
  ) async {
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 16));
      if ((await tester.runAsync(done))!) return;
    }
    fail('The photos were not stored in time');
  }

  List<Override> overrides() => [
    appDatabaseProvider.overrideWithValue(db),
    mediaRootProvider.overrideWith((ref) async => root),
    imageProcessorProvider.overrideWithValue(FakeImageProcessor()),
    photoSourceProvider.overrideWithValue(photos),
  ];

  Future<void> pumpGrid(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp(theme: AppTheme.light(), home: const NotesScreen()),
      ),
    );
    await settle(tester);
  }

  Future<Note> noteTitled(WidgetTester tester, String title) async =>
      (await tester.runAsync(
        () async => (await db.noteDao.loadShelf(
          Shelf.active,
        )).firstWhere((note) => note.title == title),
      ))!;

  testWidgets('photos chosen in the editor show on the page and the card', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpGrid(tester);
    photos.picks = [photo('front.jpg'), photo('back.jpg')];

    await tester.tap(find.text('Bike'));
    await settle(tester);
    await tester.tap(find.byTooltip('Add image'));
    await settle(tester);
    await tester.tap(find.text('Choose photos'));
    await pumpUntil(
      tester,
      () async => (await db.noteDao.loadShelf(
        Shelf.active,
      )).firstWhere((note) => note.title == 'Bike').attachments.length == 2,
    );
    await settle(tester);

    expect((await noteTitled(tester, 'Bike')).attachments, hasLength(2));
    expect(find.bySemanticsLabel('Image 1 of 2'), findsOneWidget);
    expect(find.bySemanticsLabel('Image 2 of 2'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await settle(tester);
    expect(find.byType(ImageMosaic), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Bike\. .*2 images')), findsOne);
    handle.dispose();
  });

  testWidgets('the viewer deletes an image, and undo puts it back', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpGrid(tester);
    final bike = await noteTitled(tester, 'Bike');
    await tester.runAsync(
      () => AttachmentRepository(
        db.noteDao,
        MediaStore(Future.value(root)),
        FakeImageProcessor(),
      ).addImages(bike.id, [photo('a.jpg'), photo('b.jpg')]),
    );
    await settle(tester);

    await tester.tap(find.text('Bike'));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Image 2 of 2'));
    await settle(tester);
    expect(find.text('2 / 2'), findsOneWidget);
    // A dark ground in both themes: the system bar icons turn light.
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AnnotatedRegion<SystemUiOverlayStyle> &&
            widget.value.statusBarIconBrightness == Brightness.light,
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Delete image'));
    await settle(tester);
    expect((await noteTitled(tester, 'Bike')).attachments, hasLength(1));
    expect(find.text('1 / 1'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect((await noteTitled(tester, 'Bike')).attachments, hasLength(2));
    handle.dispose();
  });

  testWidgets('the compose bar camera starts a note that keeps its photo', (
    tester,
  ) async {
    await pumpGrid(tester);
    photos.photo = photo('shot.jpg');

    await tester.tap(find.byTooltip('Take a photo'));
    await pumpUntil(
      tester,
      () async => (await db.noteDao.loadShelf(
        Shelf.active,
      )).any((note) => note.attachments.isNotEmpty),
    );
    await settle(tester);

    var withPhotos = [
      for (final note
          in (await tester.runAsync(
            () => db.noteDao.loadShelf(Shelf.active),
          ))!)
        if (note.attachments.isNotEmpty) note,
    ];
    expect(withPhotos, hasLength(1));
    expect(withPhotos.single.attachments, hasLength(1));

    // A photo alone is enough to copy the note, though not to share it.
    await tester.tap(find.byTooltip('More'));
    await settle(tester);
    bool enabled(String item) => tester
        .widget<PopupMenuItem<Object?>>(
          find.ancestor(
            of: find.text(item),
            matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
          ),
        )
        .enabled;
    expect(enabled('Make a copy'), isTrue);
    expect(enabled('Share'), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);

    await tester.tap(find.byTooltip('Back'));
    await settle(tester);

    // Nothing typed, but the photo is enough for the note to stay.
    withPhotos = [
      for (final note
          in (await tester.runAsync(
            () => db.noteDao.loadShelf(Shelf.active),
          ))!)
        if (note.attachments.isNotEmpty) note,
    ];
    expect(withPhotos, hasLength(1));
    expect(find.byType(ImageMosaic), findsOneWidget);
  });

  testWidgets('closing the camera without a photo opens nothing', (
    tester,
  ) async {
    await pumpGrid(tester);

    await tester.tap(find.byTooltip('Take a photo'));
    await settle(tester);

    expect(photos.cameraCalls, 1);
    expect(find.text('Take a note'), findsOneWidget);
    expect(await tester.runAsync(db.noteDao.countNotes), 8);
  });

  testWidgets('a card shows three images at most and counts the rest', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final now = DateTime(2026, 9, 15);
    final note = Note(
      id: 'n',
      type: NoteType.text,
      title: 'Walk',
      body: 'Along the river.',
      pigment: Pigment.moss,
      sortKey: 'm',
      createdAt: now,
      updatedAt: now,
      attachments: [
        for (var i = 0; i < 5; i++)
          Attachment(
            id: 'a$i',
            noteId: 'n',
            relPath: 'media/a$i.jpg',
            thumbPath: 'media/thumbs/a$i.jpg',
            width: 2048,
            height: i.isEven ? 1536 : 2731,
            bytes: 1000,
            mime: 'image/jpeg',
            sortKey: 'k$i',
            createdAt: now,
          ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 172,
                child: NoteCard(note: note, onTap: () {}),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('+2'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('5 images')), findsOneWidget);
    handle.dispose();
  });
}
