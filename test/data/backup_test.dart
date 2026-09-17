import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/drift.dart'
    show DatabaseConnection, Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/core/util/ids.dart';
import 'package:notes/core/util/sort_key.dart';
import 'package:notes/data/backup/bundle.dart';
import 'package:notes/data/backup/import_plan.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/db/note_dao.dart';
import 'package:notes/data/media/media_store.dart';
import 'package:notes/data/repository/attachment_repository.dart';
import 'package:notes/data/repository/backup_repository.dart';
import 'package:notes/data/repository/checklist_repository.dart';
import 'package:notes/data/repository/label_repository.dart';
import 'package:notes/data/repository/note_repository.dart';
import 'package:notes/data/repository/reminder_repository.dart';
import 'package:notes/data/repository/search_repository.dart';
import 'package:notes/data/seed.dart';
import 'package:notes/domain/model/note.dart';
import 'package:notes/domain/model/note_type.dart';
import 'package:notes/domain/model/pigment.dart';
import 'package:notes/domain/model/reminder_rule.dart';
import 'package:notes/domain/model/search.dart';

import '../support/fake_image_processor.dart';

/// One phone: a database, a media folder, and the repositories over them.
class _Phone {
  _Phone(this.name)
    : db = AppDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      ),
      media = Directory.systemTemp.createTempSync('notes_${name}_media_'),
      cache = Directory.systemTemp.createTempSync('notes_${name}_cache_') {
    attachments = AttachmentRepository(
      db.noteDao,
      MediaStore(Future.value(media)),
      FakeImageProcessor(),
    );
    backup = BackupRepository(
      db.backupDao,
      attachments,
      Future.value(media),
      Future.value(cache),
      appVersion: '1.7',
    );
  }

  final String name;
  final AppDatabase db;
  final Directory media;
  final Directory cache;
  late final AttachmentRepository attachments;
  late final BackupRepository backup;

  NoteRepository get notes => NoteRepository(db.noteDao);
  ChecklistRepository get lists => ChecklistRepository(db.noteDao);
  LabelRepository get labels => LabelRepository(db.noteDao);

  Future<List<Note>> all() => db.backupDao.allNotes();

  Future<Note> titled(String title) async =>
      (await all()).firstWhere((note) => note.title == title);

  Future<void> close() async {
    await db.close();
    media.deleteSync(recursive: true);
    cache.deleteSync(recursive: true);
  }
}

void main() {
  // Two phones means two databases, on purpose.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late _Phone a;
  late _Phone b;
  late Directory picked;

  setUp(() {
    a = _Phone('a');
    b = _Phone('b');
    picked = Directory.systemTemp.createTempSync('notes_picked_');
  });

  tearDown(() async {
    await a.close();
    await b.close();
    picked.deleteSync(recursive: true);
  });

  File photo(String name, int size) =>
      File('${picked.path}/$name')
        ..writeAsBytesSync(List.generate(size, (i) => (i * 7 + size) % 256));

  /// A bit of everything: text and lists, colours, pins, the archive, the
  /// trash, reminders, labels, and images.
  Future<void> fill(_Phone phone) async {
    final home = await phone.labels.create('Home');
    final travel = await phone.labels.create('Travel');

    final flat = await phone.notes.create(
      title: 'Flat viewing',
      body: 'Ask about the boiler.\nAnd the parking spot.',
      pigment: Pigment.verdigris,
    );
    await phone.notes.setPinned(flat.id, pinned: true);
    await phone.labels.setOnNotes([flat.id], home.id, on: true);
    await ReminderRepository(phone.db.noteDao)
        .set(flat.id, DateTime(2026, 10, 2, 18, 30), rule: ReminderRule.weekly);

    final packing = await phone.notes.create(
      type: NoteType.checklist,
      title: 'Packing',
      pigment: Pigment.amber,
    );
    final passport = await phone.lists.add(packing.id, text: 'Passport');
    await phone.lists.add(packing.id, text: 'Charger');
    final adapter = await phone.lists.add(packing.id, text: 'Adapter');
    await phone.lists.setIndent(packing.id, adapter.id, 1);
    await phone.lists.setChecked(packing.id, passport.id, checked: true);
    await phone.labels.setOnNotes([packing.id], travel.id, on: true);
    await phone.labels.setOnNotes([packing.id], home.id, on: true);
    await phone.attachments.addImages(packing.id, [
      photo('map.jpg', 300),
      photo('ticket.jpg', 420),
    ]);

    final old = await phone.notes.create(title: 'Old lease', body: 'Signed.');
    await phone.notes.setArchived(old.id, archived: true);

    final gone = await phone.notes.create(title: 'Gone', body: 'Deleted.');
    await phone.attachments.addImages(gone.id, [photo('gone.jpg', 128)]);
    await phone.notes.delete(gone.id);
  }

  Future<File> exportFrom(_Phone phone) async =>
      (await phone.backup.export(at: DateTime.utc(2026, 9, 16, 10, 5))).file;

  Future<ImportPlan> importInto(
    _Phone phone,
    File file,
    ImportMode mode,
  ) async => phone.backup.import(await phone.backup.preview(file), mode);

  Future<Map<String, String>> entries(File zip) async {
    final input = InputFileStream(zip.path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      return {
        for (final file in archive.files)
          if (file.isFile)
            file.name: file.name.endsWith('.json')
                ? utf8.decode(file.readBytes()!)
                : base64.encode(file.readBytes()!),
      };
    } finally {
      input.closeSync();
    }
  }

  group('export then replace', () {
    test('brings back every note, label, and image as it was', () async {
      await fill(a);
      final file = await exportFrom(a);

      final plan = await importInto(b, file, ImportMode.replace);

      expect(await b.all(), await a.all());
      expect(
        await b.db.backupDao.liveLabels(),
        await a.db.backupDao.liveLabels(),
      );
      expect(plan.notesAdded, 4);
      expect(plan.labelsAdded, 2);
      expect(plan.imagesAdded, 3);

      for (final note in await a.all()) {
        for (final image in note.attachments) {
          for (final path in [image.relPath, image.thumbPath]) {
            expect(
              MediaStore.resolve(b.media, path).readAsBytesSync(),
              MediaStore.resolve(a.media, path).readAsBytesSync(),
              reason: path,
            );
          }
        }
      }
    });

    test('an export of the import is the same file, entry for entry', () async {
      await fill(a);
      final first = await exportFrom(a);
      await importInto(b, first, ImportMode.replace);

      final second = await exportFrom(b);

      expect(await entries(second), await entries(first));
    });

    test('keeps each note in its shelf, with its reminder and list', () async {
      await fill(a);
      await importInto(b, await exportFrom(a), ImportMode.replace);

      expect(
        [
          for (final note in await b.db.noteDao.loadShelf(Shelf.active))
            note.title,
        ],
        ['Flat viewing', 'Packing'],
      );
      expect(
        [
          for (final note in await b.db.noteDao.loadShelf(Shelf.archived))
            note.title,
        ],
        ['Old lease'],
      );
      expect(
        [
          for (final note in await b.db.noteDao.loadShelf(Shelf.trash))
            note.title,
        ],
        ['Gone'],
      );
      final flat = await b.titled('Flat viewing');
      expect(flat.pinned, isTrue);
      expect(flat.reminderRule, ReminderRule.weekly);
      expect(flat.reminderAt, DateTime(2026, 10, 2, 18, 30));
      final packing = await b.titled('Packing');
      expect(
        [
          for (final item in packing.items)
            (item.text, item.checked, item.indent),
        ],
        [('Passport', true, 0), ('Charger', false, 0), ('Adapter', false, 1)],
      );
      expect(
        [for (final label in packing.labels) label.name],
        ['Home', 'Travel'],
      );
    });

    test('deletes what was here before, and its files once swept', () async {
      await fill(a);
      await b.notes.create(title: 'Only on b');
      final mine = await b.notes.create(title: 'Photo on b');
      await b.attachments.addImages(mine.id, [photo('b.jpg', 64)]);
      await b.labels.create('Errands');
      final bImage = (await b.titled('Photo on b')).attachments.single;

      final preview = await b.backup.preview(await exportFrom(a));
      expect(preview.replace.notesRemoved, 2);
      await b.backup.import(preview, ImportMode.replace);
      await b.attachments.sweep(dropRemoved: false);

      expect([
        for (final note in await b.all()) note.title,
      ], isNot(contains('Only on b')));
      expect(
        [for (final label in await b.db.backupDao.liveLabels()) label.name],
        ['Home', 'Travel'],
      );
      expect(MediaStore.resolve(b.media, bImage.relPath).existsSync(), isFalse);
    });

    test('a file whose images are here already is imported again', () async {
      await fill(a);
      final file = await exportFrom(a);

      await importInto(a, file, ImportMode.replace);
      await a.attachments.sweep(dropRemoved: true);

      final packing = await a.titled('Packing');
      expect(packing.attachments, hasLength(2));
      for (final image in packing.attachments) {
        expect(MediaStore.resolve(a.media, image.relPath).existsSync(), isTrue);
      }
    });
  });

  group('search', () {
    Future<List<String>> found(_Phone phone, String text) async => [
      for (final note in (await SearchRepository(
        phone.db.searchDao,
      ).search(SearchQuery(text: text))).notes)
        note.title,
    ];

    test('finds imported notes by title, item, and label', () async {
      await fill(a);
      await b.notes.create(title: 'Adapter drawer');

      await importInto(b, await exportFrom(a), ImportMode.replace);

      expect(await found(b, 'boiler'), ['Flat viewing']);
      expect(await found(b, 'adapter'), ['Packing']);
      expect(await found(b, 'travel'), ['Packing']);
    });

    test('finds notes a merge added or changed', () async {
      await b.notes.create(title: 'Adapter drawer');
      await fill(a);

      await importInto(b, await exportFrom(a), ImportMode.merge);

      expect(
        await found(b, 'adapter'),
        unorderedEquals(['Packing', 'Adapter drawer']),
      );
      expect(
        await found(b, 'home'),
        unorderedEquals(['Flat viewing', 'Packing']),
      );
    });
  });

  group('merge', () {
    test('adds new notes above the notes here, in the file order', () async {
      await a.notes.create(title: 'A first');
      await a.notes.create(title: 'A second');
      await b.notes.create(title: 'B only');

      final plan = await importInto(b, await exportFrom(a), ImportMode.merge);

      expect(plan.notesAdded, 2);
      expect(
        [
          for (final note in await b.db.noteDao.loadShelf(Shelf.active))
            note.title,
        ],
        ['A second', 'A first', 'B only'],
      );
    });

    test('takes the later edit of a note both phones hold', () async {
      await fill(a);
      await importInto(b, await exportFrom(a), ImportMode.replace);
      final packing = await a.titled('Packing');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await a.notes.saveText(packing.id, title: 'Packing for Porto');
      await a.lists.removeEmpty(packing.id);
      final charger = packing.items.firstWhere(
        (item) => item.text == 'Charger',
      );
      await a.lists.remove(packing.id, charger.id);
      await a.labels.setOnNotes(
        [packing.id],
        packing.labels.firstWhere((label) => label.name == 'Home').id,
        on: false,
      );
      final bFlat = await b.titled('Flat viewing');
      await b.notes.reorder(bFlat.id, prevKey: 'b');
      final bKey = (await b.titled('Flat viewing')).sortKey;

      final plan = await importInto(b, await exportFrom(a), ImportMode.merge);

      expect(plan.notesUpdated, 1);
      expect(plan.notesKept, 3);
      final merged = await b.titled('Packing for Porto');
      expect(
        [for (final item in merged.items) item.text],
        ['Passport', 'Adapter'],
      );
      expect([for (final label in merged.labels) label.name], ['Travel']);
      // Flat viewing was moved on b after the export, so b's copy is newer.
      expect((await b.titled('Flat viewing')).sortKey, bKey);
    });

    test('keeps a note edited here after the file was made', () async {
      await a.notes.create(title: 'Shared', body: 'From a');
      await importInto(b, await exportFrom(a), ImportMode.replace);
      final file = await exportFrom(a);
      final shared = await b.titled('Shared');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await b.notes.saveText(shared.id, body: 'Edited on b');

      final plan = await importInto(b, file, ImportMode.merge);

      expect(plan.notesKept, 1);
      expect(plan.notesUpdated, 0);
      expect((await b.titled('Shared')).body, 'Edited on b');
    });

    test(
      'a label named like one here, in any case, becomes that label',
      () async {
        final note = await a.notes.create(title: 'Tiles');
        final label = await a.labels.create('HOME');
        await a.labels.setOnNotes([note.id], label.id, on: true);
        await b.labels.create('Errands');
        final bHome = await b.labels.create('home');

        final plan = await importInto(b, await exportFrom(a), ImportMode.merge);

        expect(plan.labelsAdded, 0);
        expect(
          [for (final label in await b.db.backupDao.liveLabels()) label.name],
          ['Errands', 'home'],
        );
        expect((await b.titled('Tiles')).labels.single.id, bHome.id);
      },
    );

    test('a label renamed in the file to a name taken here joins that label', () async {
      final note = await a.notes.create(title: 'Tiles');
      final home = await a.labels.create('Home');
      await a.labels.setOnNotes([note.id], home.id, on: true);
      await importInto(b, await exportFrom(a), ImportMode.replace);
      final work = await b.labels.create('Work');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await a.labels.rename(home.id, 'Work');
      await a.notes.saveText(note.id, body: 'Grey, matte');

      await importInto(b, await exportFrom(a), ImportMode.merge);

      expect(
        [for (final label in await b.db.backupDao.liveLabels()) label.name],
        ['Home', 'Work'],
      );
      expect((await b.titled('Tiles')).labels.single.id, work.id);
    });

    test('new labels go after the labels here', () async {
      await a.labels.create('Zebra');
      await a.labels.create('Apple');
      await b.labels.create('Mango');

      final plan = await importInto(b, await exportFrom(a), ImportMode.merge);

      expect(plan.labelsAdded, 2);
      expect(
        [for (final label in await b.db.backupDao.liveLabels()) label.name],
        ['Mango', 'Zebra', 'Apple'],
      );
    });

    test(
      'a label deleted here after the file was made stays deleted',
      () async {
        final note = await a.notes.create(title: 'Tiles');
        final label = await a.labels.create('Home');
        await a.labels.setOnNotes([note.id], label.id, on: true);
        final file = await exportFrom(a);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await a.labels.delete(label.id);

        await importInto(a, file, ImportMode.merge);

        expect(await a.db.backupDao.liveLabels(), isEmpty);
      },
    );

    test('images of kept notes are swept, images of new notes stay', () async {
      await fill(a);
      final file = await exportFrom(a);
      final preview = await b.backup.preview(file);
      expect(preview.merge.imagesAdded, 3);

      await b.backup.import(preview, ImportMode.merge);
      await b.attachments.sweep(dropRemoved: false);

      final images = [for (final note in await b.all()) ...note.attachments];
      expect(images, hasLength(3));
      for (final image in images) {
        expect(MediaStore.resolve(b.media, image.relPath).existsSync(), isTrue);
      }
    });
  });

  test('exports started together run one after the other', () async {
    await fill(a);

    final first = a.backup.export(at: DateTime.utc(2026, 9, 16, 10, 5));
    final second = a.backup.export(at: DateTime.utc(2026, 9, 16, 10, 5));
    await first;
    final file = (await second).file;

    final preview = await b.backup.preview(file);
    expect(preview.bundle.notes, hasLength(4));
    expect(preview.bundle.imageCount, 3);
  });

  group('progress', () {
    test('an export counts its images as they go in', () async {
      await fill(a);
      final seen = <(int, int)>[];

      await a.backup.export(
        onProgress: (done, total) => seen.add((done, total)),
      );

      expect(seen.first, (0, 3));
      expect(seen.last, (3, 3));
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i].$1, greaterThanOrEqualTo(seen[i - 1].$1));
      }
    });

    test('an import counts its images as they come out', () async {
      await fill(a);
      final preview = await b.backup.preview(await exportFrom(a));
      final seen = <(int, int)>[];

      await b.backup.import(
        preview,
        ImportMode.replace,
        onProgress: (done, total) => seen.add((done, total)),
      );

      expect(seen.first, (0, 3));
      expect(seen.last, (3, 3));
    });
  });

  group('preview', () {
    test('writes nothing', () async {
      await fill(a);
      await b.notes.create(title: 'Mine');

      final preview = await b.backup.preview(await exportFrom(a));

      expect(preview.merge.notesAdded, 4);
      expect(preview.replace.notesRemoved, 1);
      expect([for (final note in await b.all()) note.title], ['Mine']);
      expect(MediaStore(Future.value(b.media)).listAll(), completion(isEmpty));
    });
  });

  test('writes times in UTC to the millisecond', () async {
    await a.notes.create(title: 'Timed');
    final file = (await a.backup.export(
      at: DateTime.utc(2026, 9, 16, 10, 5, 7, 123, 456),
    )).file;

    final written = await entries(file);
    final manifest = jsonDecode(written['manifest.json']!) as Map;
    expect(manifest['exportedAt'], '2026-09-16T10:05:07.123Z');
    final note = (jsonDecode(written['notes.json']!) as List).single as Map;
    expect(
      note['createdAt'],
      matches(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$')),
    );
  });

  group('files that cannot be imported', () {
    File zip(Map<String, String> files) {
      final encoder = ZipEncoder();
      final archive = Archive();
      for (final MapEntry(key: name, value: text) in files.entries) {
        archive.addFile(ArchiveFile.bytes(name, utf8.encode(text)));
      }
      return File('${picked.path}/made.zip')
        ..writeAsBytesSync(encoder.encode(archive));
    }

    String manifest({
      int version = Bundle.schemaVersion,
      String app = 'notes',
    }) => jsonEncode({'app': app, 'schemaVersion': version});

    Future<BundleProblem?> problemWith(File file) async {
      try {
        await b.backup.preview(file);
        return null;
      } on BundleException catch (error) {
        return error.problem;
      }
    }

    test('a file that is not a zip', () async {
      final file = File('${picked.path}/notes.txt')..writeAsStringSync('hello');
      expect(await problemWith(file), BundleProblem.notAnExport);
    });

    test('a zip without the manifest, or with another app’s', () async {
      expect(
        await problemWith(zip({'notes.json': '[]', 'labels.json': '[]'})),
        BundleProblem.notAnExport,
      );
      expect(
        await problemWith(
          zip({'manifest.json': manifest(app: 'other'), 'notes.json': '[]'}),
        ),
        BundleProblem.notAnExport,
      );
    });

    test('an export from a newer version', () async {
      expect(
        await problemWith(
          zip({
            'manifest.json': manifest(version: Bundle.schemaVersion + 1),
            'notes.json': '[]',
            'labels.json': '[]',
          }),
        ),
        BundleProblem.newerVersion,
      );
    });

    test('notes that do not parse', () async {
      expect(
        await problemWith(
          zip({
            'manifest.json': manifest(),
            'notes.json': '[{"id": "n1"}]',
            'labels.json': '[]',
          }),
        ),
        BundleProblem.damaged,
      );
    });

    test('an id that would reach outside the media folder', () async {
      final note = {
        'id': 'n1',
        'sortKey': 'n',
        'createdAt': '2026-09-16T10:00:00.000Z',
        'updatedAt': '2026-09-16T10:00:00.000Z',
        'images': [
          {
            'id': '../../databases/notes',
            'width': 1,
            'height': 1,
            'bytes': 1,
            'mime': 'image/jpeg',
            'sortKey': 'n',
            'createdAt': '2026-09-16T10:00:00.000Z',
          },
        ],
      };
      expect(
        await problemWith(
          zip({
            'manifest.json': manifest(),
            'notes.json': jsonEncode([note]),
            'labels.json': '[]',
          }),
        ),
        BundleProblem.damaged,
      );
    });

    test('an image missing from the file is left out, not fatal', () async {
      final note = {
        'id': 'n1',
        'title': 'Kept',
        'sortKey': 'n',
        'createdAt': '2026-09-16T10:00:00.000Z',
        'updatedAt': '2026-09-16T10:00:00.000Z',
        'labels': ['nowhere'],
        'images': [
          {
            'id': 'i1',
            'width': 1,
            'height': 1,
            'bytes': 1,
            'mime': 'image/jpeg',
            'sortKey': 'n',
            'createdAt': '2026-09-16T10:00:00.000Z',
          },
        ],
      };
      final preview = await b.backup.preview(
        zip({
          'manifest.json': manifest(),
          'notes.json': jsonEncode([note]),
          'labels.json': '[]',
        }),
      );

      expect(preview.merge.imagesMissing, 1);
      await b.backup.import(preview, ImportMode.merge);
      final kept = await b.titled('Kept');
      expect(kept.attachments, isEmpty);
      expect(kept.labels, isEmpty);
    });
  });

  test(
    'replacing with an empty export does not bring the starter notes back',
    () async {
      await seedIfEmpty(b.db.noteDao);
      await importInto(b, await exportFrom(a), ImportMode.replace);

      await seedIfEmpty(b.db.noteDao);

      expect(await b.notes.count(), 0);
    },
  );

  test('an import leaves the sync flag set on what it wrote', () async {
    await fill(a);
    await importInto(b, await exportFrom(a), ImportMode.replace);

    final rows = await b.db.select(b.db.notes).get();
    expect(rows, hasLength(4));
    expect(rows.every((row) => row.dirty), isTrue);
  });
  test('exports and imports 5,000 notes', tags: 'perf', () async {
    const noteCount = 5000;
    final now = DateTime.now().millisecondsSinceEpoch;
    final label = await a.labels.create('Everything');
    final noteRows = <NotesCompanion>[];
    final itemRows = <ChecklistItemsCompanion>[];
    final linkRows = <NoteLabelsCompanion>[];
    final keys = SortKey.spread(noteCount);
    final itemKeys = SortKey.spread(8);
    for (var i = 0; i < noteCount; i++) {
      final id = newId();
      final isList = i % 5 == 0;
      noteRows.add(
        NotesCompanion.insert(
          id: id,
          sortKey: keys[i],
          createdAtMs: now,
          updatedAtMs: now,
          type: Value(isList ? NoteType.checklist : NoteType.text),
          title: Value('Note number $i'),
          body: Value(isList ? '' : 'A body of some forty words ' * 8),
        ),
      );
      if (isList) {
        for (var j = 0; j < 8; j++) {
          itemRows.add(
            ChecklistItemsCompanion.insert(
              id: newId(),
              noteId: id,
              sortKey: itemKeys[j],
              updatedAtMs: now,
              content: Value('Item $j of list $i'),
            ),
          );
        }
      }
      if (i.isEven) {
        linkRows.add(
          NoteLabelsCompanion.insert(
            noteId: id,
            labelId: label.id,
            updatedAtMs: now,
          ),
        );
      }
    }
    await a.db.batch((batch) {
      batch
        ..insertAll(a.db.notes, noteRows)
        ..insertAll(a.db.checklistItems, itemRows)
        ..insertAll(a.db.noteLabels, linkRows);
    });

    final watch = Stopwatch()..start();
    final file = await exportFrom(a);
    final exported = watch.elapsedMilliseconds;

    watch.reset();
    final preview = await b.backup.preview(file);
    final previewed = watch.elapsedMilliseconds;

    watch.reset();
    await b.backup.import(preview, ImportMode.replace);
    final replaced = watch.elapsedMilliseconds;

    watch.reset();
    await b.backup.import(await b.backup.preview(file), ImportMode.merge);
    final merged = watch.elapsedMilliseconds;

    // Recorded so the numbers can go into the plan.
    // ignore: avoid_print
    print({
      'export': '${exported}ms',
      'preview': '${previewed}ms',
      'replace': '${replaced}ms',
      'merge, nothing newer': '${merged}ms',
      'size': '${file.lengthSync() ~/ 1024} KB',
    });
    expect(await b.notes.count(), noteCount);
  });
}
