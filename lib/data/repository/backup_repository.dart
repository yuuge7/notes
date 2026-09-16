import 'dart:io';

import 'package:notes/data/backup/bundle.dart';
import 'package:notes/data/backup/bundle_archive.dart';
import 'package:notes/data/backup/import_plan.dart';
import 'package:notes/data/db/backup_dao.dart';
import 'package:notes/data/media/media_store.dart';
import 'package:notes/data/repository/attachment_repository.dart';
import 'package:notes/domain/model/attachment.dart';
import 'package:path/path.dart' as p;

/// A file read for import, with what importing it would do either way.
class ImportPreview {
  const ImportPreview({
    required this.file,
    required this.bundle,
    required this.merge,
    required this.replace,
  });

  final File file;
  final Bundle bundle;
  final ImportPlan merge;
  final ImportPlan replace;

  ImportPlan planFor(ImportMode mode) =>
      mode == ImportMode.merge ? merge : replace;
}

/// Export to one file, and import back from one.
class BackupRepository {
  BackupRepository(
    this._dao,
    this._attachments,
    this._mediaRoot,
    this._cacheRoot, {
    required this._appVersion,
  });

  final BackupDao _dao;
  final AttachmentRepository _attachments;
  final Future<Directory> _mediaRoot;
  final Future<Directory> _cacheRoot;
  final String _appVersion;

  /// Past this many notes, an import indexes search once at the end.
  static const _bulkNotes = 200;

  /// The export being written, which the next one waits for.
  Future<void> _exports = Future.value();

  /// Writes every note, label, and image to a zip in the app's cache, and
  /// returns the file with the bundle as written. The previous export's file
  /// is cleared first; once handed to the system it is no longer needed.
  ///
  /// Exports run one at a time. A sheet closed mid-export leaves its export
  /// running, and one opened again straight after must not clear that file
  /// away, or write over it under the same name, while it is being written.
  Future<({File file, Bundle bundle})> export({DateTime? at}) {
    final run = _exports.then((_) => _export(at));
    _exports = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<({File file, Bundle bundle})> _export(DateTime? at) async {
    final exportedAt = at ?? DateTime.now();
    final bundle = Bundle(
      notes: await _dao.allNotes(),
      labels: await _dao.liveLabels(),
      appVersion: _appVersion,
      exportedAt: exportedAt,
    );
    final folder = Directory(p.join((await _cacheRoot).path, 'exports'));
    if (folder.existsSync()) await folder.delete(recursive: true);
    await folder.create(recursive: true);
    final file = File(p.join(folder.path, Bundle.fileName(exportedAt)));
    final written = await BundleArchive.write(
      bundle,
      zipPath: file.path,
      mediaRoot: (await _mediaRoot).path,
    );
    return (file: file, bundle: written);
  }

  /// Reads the export at [file] and works out what importing it would do.
  /// Nothing is written. Throws [BundleException] for a file that cannot be
  /// imported.
  Future<ImportPreview> preview(File file) async {
    final bundle = await BundleArchive.read(file.path);
    final local = await _dao.localState();
    return ImportPreview(
      file: file,
      bundle: bundle,
      merge: ImportPlan.of(bundle, local, ImportMode.merge),
      replace: ImportPlan.of(bundle, local, ImportMode.replace),
    );
  }

  /// Imports [preview] under [mode] and returns what was done.
  ///
  /// The images are unpacked first, then every write happens in one
  /// transaction, worked out again from the notes as they are at that moment.
  /// If the transaction fails, nothing is written and the unpacked files are
  /// removed. Images unpacked for notes that stay as they are here are swept
  /// away with other unused files.
  Future<ImportPlan> import(ImportPreview preview, ImportMode mode) async {
    final bundle = preview.bundle;
    final root = await _mediaRoot;
    final images = [for (final note in bundle.notes) ...note.attachments];

    return _attachments.holdFiles(
      [
        for (final image in images) ...[image.relPath, image.thumbPath],
      ],
      () async {
        final unpack = [
          for (final image in images)
            if (!_onDisk(root, image)) image,
        ];
        final created = [
          for (final image in unpack)
            for (final path in [image.relPath, image.thumbPath])
              if (!MediaStore.resolve(root, path).existsSync()) path,
        ];
        try {
          final sizes = await BundleArchive.extract(
            preview.file.path,
            unpack,
            mediaRoot: root.path,
          );
          final unpacked = bundle.copyWith(
            notes: [
              for (final note in bundle.notes)
                note.copyWith(
                  attachments: [
                    for (final image in note.attachments)
                      image.copyWith(bytes: sizes[image.id] ?? image.bytes),
                  ],
                ),
            ],
          );
          return await _dao.transaction(() async {
            final local = await _dao.localState();
            final plan = ImportPlan.of(unpacked, local, mode);
            Future<void> write() async {
              if (mode == ImportMode.replace) await _dao.wipe();
              await _dao.writeLabels(plan.labels);
              await _dao.writeNotes(
                plan.notes,
                existing: mode == ImportMode.replace
                    ? const {}
                    : local.notes.keys.toSet(),
              );
            }

            // Search keeps up note by note as they are written. For many
            // notes, indexing everything once at the end is far quicker.
            if (mode == ImportMode.replace || plan.notes.length > _bulkNotes) {
              await _dao.writeInBulk(write);
            } else {
              await write();
            }
            return plan;
          });
        } on Object {
          for (final path in created) {
            try {
              await MediaStore.resolve(root, path).delete();
            } on FileSystemException {
              // Never written.
            }
          }
          rethrow;
        }
      },
    );
  }

  /// Whether [image] is here already, as an earlier import or the note it
  /// came from left it. Images are never edited, so the same id and size
  /// mean the same photo.
  static bool _onDisk(Directory root, Attachment image) {
    final file = MediaStore.resolve(root, image.relPath);
    return file.existsSync() &&
        file.lengthSync() == image.bytes &&
        MediaStore.resolve(root, image.thumbPath).existsSync();
  }
}
