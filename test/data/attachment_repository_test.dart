import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/media/media_janitor.dart';
import 'package:notes/data/media/media_store.dart';
import 'package:notes/data/repository/attachment_repository.dart';
import 'package:notes/data/repository/note_repository.dart';

import '../support/fake_image_processor.dart';

/// Images on notes, against a real database and real files in a temporary
/// folder: what is stored, and that nothing is left on disk once a note has
/// gone for good.
void main() {
  late AppDatabase db;
  late Directory root;
  late Directory picked;
  late MediaStore store;
  late FakeImageProcessor processor;
  late NoteRepository notes;
  late AttachmentRepository attachments;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    root = Directory.systemTemp.createTempSync('notes_media_');
    picked = Directory.systemTemp.createTempSync('notes_picked_');
    store = MediaStore(Future.value(root));
    processor = FakeImageProcessor();
    notes = NoteRepository(db.noteDao);
    attachments = AttachmentRepository(db.noteDao, store, processor);
  });

  tearDown(() async {
    await db.close();
    root.deleteSync(recursive: true);
    picked.deleteSync(recursive: true);
  });

  File photo(String name) =>
      File('${picked.path}/$name')..writeAsBytesSync(List.filled(64, 7));

  Future<void> sweepAfterWrites(MediaJanitor janitor) async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await janitor.idle;
    }
  }

  test('photos added to a note are stored under media, in order', () async {
    final note = await notes.create(title: 'Bike');

    final result = await attachments.addImages(note.id, [
      photo('front.jpg'),
      photo('back.jpg'),
    ]);

    expect(result, (added: 2, failed: 0));
    final images = (await notes.load(note.id))!.attachments;
    expect(images, hasLength(2));
    expect(images.first.sortKey.compareTo(images.last.sortKey), lessThan(0));
    for (final image in images) {
      expect(image.relPath, 'media/${image.id}.jpg');
      expect(image.thumbPath, 'media/thumbs/${image.id}.jpg');
      expect((await store.file(image.relPath)).existsSync(), isTrue);
      expect((await store.file(image.thumbPath)).existsSync(), isTrue);
      expect((image.width, image.height), (2048, 1536));
    }
    // The picked files are the picker's, not the app's to delete.
    expect(File('${picked.path}/front.jpg').existsSync(), isTrue);
  });

  test('more photos go after the ones a note already has', () async {
    final note = await notes.create(title: 'Bike');
    await attachments.addImages(note.id, [photo('one.jpg')]);
    await attachments.addImages(note.id, [photo('two.jpg')]);

    final images = await attachments.of(note.id);
    expect(images.first.sortKey.compareTo(images.last.sortKey), lessThan(0));
  });

  test('batches added at once keep their order', () async {
    final note = await notes.create(title: 'Bike');
    File sized(String name, int length) =>
        File('${picked.path}/$name')..writeAsBytesSync(List.filled(length, 1));
    processor.gate = Completer<void>();

    final first = attachments.addImages(note.id, [
      sized('a.jpg', 10),
      sized('b.jpg', 20),
    ]);
    final second = attachments.addImages(note.id, [sized('c.jpg', 30)]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    processor.gate!.complete();
    await Future.wait([first, second]);

    final images = await attachments.of(note.id);
    expect([for (final image in images) image.bytes], [10, 20, 30]);
    expect({for (final image in images) image.sortKey}, hasLength(3));
  });

  test('a new note whose only image was removed is not discarded', () async {
    final note = await notes.create();
    await attachments.addImages(note.id, [photo('front.jpg')]);
    final image = (await attachments.of(note.id)).single;
    await attachments.remove(image.id);

    // Closing the page tries to discard it; the undo must still work.
    expect(await notes.discardIfBlank(note.id), isFalse);
    await attachments.restore(image.id);

    expect(await attachments.of(note.id), hasLength(1));
    expect(await attachments.sweep(dropRemoved: false), 0);
  });

  test('a photo that cannot be read is skipped and leaves no files', () async {
    final note = await notes.create(title: 'Bike');

    final result = await attachments.addImages(note.id, [
      photo('good.jpg'),
      photo('broken.jpg'),
    ]);

    expect(result, (added: 1, failed: 1));
    expect(await store.listAll(), hasLength(2));
  });

  test('a removed image keeps its files for undo until start-up', () async {
    final note = await notes.create(title: 'Bike');
    await attachments.addImages(note.id, [photo('front.jpg')]);
    final image = (await attachments.of(note.id)).single;

    await attachments.remove(image.id);
    expect(await attachments.of(note.id), isEmpty);
    expect(await attachments.sweep(dropRemoved: false), 0);

    await attachments.restore(image.id);
    expect(await attachments.of(note.id), hasLength(1));

    await attachments.remove(image.id);
    expect(await attachments.sweep(dropRemoved: true), 2);
    expect(await store.listAll(), isEmpty);
  });

  test('a note in the trash keeps its images', () async {
    final note = await notes.create(title: 'Bike');
    await attachments.addImages(note.id, [photo('front.jpg')]);

    await notes.delete(note.id);

    expect(await attachments.sweep(dropRemoved: true), 0);
    expect(await store.listAll(), hasLength(2));
  });

  for (final (way, deleteForGood) in <(String, Future<void> Function(String))>[
    ('delete forever', (id) async {
      final notes = NoteRepository(db.noteDao);
      await notes.delete(id);
      await notes.deleteForever(id);
    }),
    ('empty trash', (id) async {
      final notes = NoteRepository(db.noteDao);
      await notes.delete(id);
      await notes.emptyTrash();
    }),
    ('the trash purge', (id) async {
      final notes = NoteRepository(db.noteDao);
      await notes.delete(id);
      await db.noteDao.updateNote(
        id,
        NotesCompanion(
          deletedAtMs: Value(
            DateTime.now()
                .subtract(const Duration(days: 30))
                .millisecondsSinceEpoch,
          ),
        ),
      );
      await notes.purgeExpiredTrash();
    }),
  ]) {
    test('no files are left after $way', () async {
      final janitor = MediaJanitor(
        attachments,
        db.noteDao.watchAttachmentWrites(),
        delay: Duration.zero,
      )..start();
      addTearDown(janitor.dispose);
      final kept = await notes.create(title: 'Kept');
      final gone = await notes.create(title: 'Gone');
      await attachments.addImages(kept.id, [photo('kept.jpg')]);
      await attachments.addImages(gone.id, [photo('a.jpg'), photo('b.jpg')]);
      await sweepAfterWrites(janitor);
      expect(await store.listAll(), hasLength(6));

      await deleteForGood(gone.id);
      await sweepAfterWrites(janitor);

      final left = await store.listAll();
      final image = (await attachments.of(kept.id)).single;
      expect(left, unorderedEquals([image.relPath, image.thumbPath]));
    });
  }

  test('a copy gets files of its own', () async {
    final original = await notes.create(title: 'Bike');
    await attachments.addImages(original.id, [photo('front.jpg')]);
    final copy = await notes.duplicate(original.id);

    await attachments.copyAll(from: original.id, to: copy.id);
    await notes.delete(original.id);
    await notes.deleteForever(original.id);
    await attachments.sweep(dropRemoved: true);

    final image = (await attachments.of(copy.id)).single;
    expect((await store.file(image.relPath)).existsSync(), isTrue);
    expect((await store.file(image.thumbPath)).existsSync(), isTrue);
    expect(await store.listAll(), hasLength(2));
  });

  test('files nothing refers to are swept at start-up', () async {
    final note = await notes.create(title: 'Bike');
    await attachments.addImages(note.id, [photo('front.jpg')]);
    (await store.prepare('media/left-behind.jpg')).writeAsBytesSync([1, 2, 3]);

    final janitor = MediaJanitor(
      attachments,
      db.noteDao.watchAttachmentWrites(),
    )..start();
    addTearDown(janitor.dispose);
    await janitor.idle;

    expect(await store.listAll(), hasLength(2));
    expect(await store.listAll(), isNot(contains('media/left-behind.jpg')));
  });

  test('a sweep while photos are being added leaves them alone', () async {
    final note = await notes.create(title: 'Bike');
    processor.gate = Completer<void>();

    final adding = attachments.addImages(note.id, [photo('slow.jpg')]);
    // Let the processor write its files and wait at the gate.
    for (var i = 0; i < 10 && (await store.listAll()).length < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(await store.listAll(), hasLength(2));

    expect(await attachments.sweep(dropRemoved: true), 0);

    processor.gate!.complete();
    await adding;
    final image = (await attachments.of(note.id)).single;
    expect((await store.file(image.relPath)).existsSync(), isTrue);
  });
}
