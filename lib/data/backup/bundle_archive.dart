import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:notes/data/backup/bundle.dart';
import 'package:notes/data/media/media_store.dart';
import 'package:notes/domain/model/attachment.dart';
import 'package:notes/domain/model/note.dart';

/// Told how far a long piece of work has got: [done] of [total] images.
typedef Progress = void Function(int done, int total);

/// Writes and reads the export zip.
///
/// Every method does its work on an isolate of its own: a zip of a few hundred
/// photos takes seconds to write, and the page showing progress must keep
/// drawing meanwhile.
abstract final class BundleArchive {
  /// Writes [bundle] as a zip at [zipPath], taking each image and its
  /// thumbnail from under [mediaRoot], and returns the bundle as written.
  ///
  /// An image whose file is gone is left out rather than failing the export,
  /// and counted in [Bundle.missingImages].
  static Future<Bundle> write(
    Bundle bundle, {
    required String zipPath,
    required String mediaRoot,
    Progress? onProgress,
  }) => _reporting(
    onProgress,
    (report) => _write(bundle, zipPath, mediaRoot, report),
  );

  /// Reads the bundle in the zip at [zipPath] without unpacking its images.
  ///
  /// Throws [BundleException]. An image the notes list but the zip lacks is
  /// dropped from its note and counted in [Bundle.missingImages].
  static Future<Bundle> read(String zipPath) =>
      Isolate.run(() => _read(zipPath));

  /// Unpacks [images] from the zip at [zipPath] to their places under
  /// [mediaRoot], and returns the size each image came to, by id.
  ///
  /// A thumbnail missing from the zip is replaced by a copy of its image.
  static Future<Map<String, int>> extract(
    String zipPath,
    List<Attachment> images, {
    required String mediaRoot,
    Progress? onProgress,
  }) => _reporting(
    onProgress,
    (report) => _extract(zipPath, images, mediaRoot, report),
  );

  /// Runs [work] on an isolate of its own, passing what it reports back to
  /// [onProgress] on this one.
  static Future<R> _reporting<R>(
    Progress? onProgress,
    R Function(Progress report) work,
  ) async {
    if (onProgress == null) return Isolate.run(() => work((_, _) {}));
    final port = ReceivePort()
      ..listen((message) {
        final (done, total) = message as (int, int);
        onProgress(done, total);
      });
    try {
      return await _runSending(work, port.sendPort);
    } finally {
      // Let the last report arrive before the port closes.
      await Future<void>.delayed(Duration.zero);
      port.close();
    }
  }

  /// Starts [work] on its own isolate, reporting through [send].
  ///
  /// A function of its own: a closure made inside [_reporting] would share
  /// its scope, the progress callback with it, and that cannot cross to an
  /// isolate.
  static Future<R> _runSending<R>(
    R Function(Progress report) work,
    SendPort send,
  ) => Isolate.run(() => work((done, total) => send.send((done, total))));

  static Bundle _write(
    Bundle bundle,
    String zipPath,
    String mediaRoot,
    Progress report,
  ) {
    final root = Directory(mediaRoot);
    var missing = 0;
    final notes = <Note>[];
    for (final note in bundle.notes) {
      final images = <Attachment>[];
      for (final image in note.attachments) {
        if (MediaStore.resolve(root, image.relPath).existsSync()) {
          images.add(image);
        } else {
          missing++;
        }
      }
      notes.add(note.copyWith(attachments: images));
    }
    final written = bundle.copyWith(notes: notes, missingImages: missing);

    final modified =
        (written.exportedAt ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    final encoder = ZipFileEncoder()..create(zipPath);
    try {
      void addText(String name, String text) => encoder.addArchiveFile(
        ArchiveFile.bytes(name, utf8.encode(text))..lastModTime = modified,
      );

      // Photos are JPEG already; deflating them again costs time and saves
      // nothing, so they are stored as they are.
      void addFile(String name, File file) {
        final stream = InputFileStream(file.path);
        try {
          encoder.addArchiveFile(
            ArchiveFile.stream(name, stream)
              ..compression = CompressionType.none
              ..lastModTime = modified,
          );
        } finally {
          stream.closeSync();
        }
      }

      addText(Bundle.manifestEntry, written.manifestJson());
      addText(Bundle.notesEntry, written.notesJson());
      addText(Bundle.labelsEntry, written.labelsJson());
      final total = written.imageCount;
      var done = 0;
      report(done, total);
      for (final note in written.notes) {
        for (final image in note.attachments) {
          addFile(
            Bundle.imageEntry(image),
            MediaStore.resolve(root, image.relPath),
          );
          final thumb = MediaStore.resolve(root, image.thumbPath);
          if (thumb.existsSync()) addFile(Bundle.thumbEntry(image), thumb);
          report(++done, total);
        }
      }
    } finally {
      encoder.closeSync();
    }
    return written;
  }

  static Bundle _read(String zipPath) {
    final input = InputFileStream(zipPath);
    try {
      final Archive archive;
      try {
        archive = ZipDecoder().decodeStream(input);
      } on Object {
        throw const BundleException(BundleProblem.notAnExport);
      }
      String? text(String name) {
        try {
          final bytes = archive.findFile(name)?.readBytes();
          return bytes == null ? null : utf8.decode(bytes);
        } on Object catch (error) {
          throw BundleException(BundleProblem.damaged, '$name: $error');
        }
      }

      final bundle = Bundle.decode(
        manifest: text(Bundle.manifestEntry),
        notes: text(Bundle.notesEntry),
        labels: text(Bundle.labelsEntry),
      );

      var missing = 0;
      final notes = <Note>[];
      for (final note in bundle.notes) {
        final images = <Attachment>[];
        for (final image in note.attachments) {
          if (archive.findFile(Bundle.imageEntry(image)) != null) {
            images.add(image);
          } else {
            missing++;
          }
        }
        notes.add(note.copyWith(attachments: images));
      }
      return bundle.copyWith(notes: notes, missingImages: missing);
    } finally {
      input.closeSync();
    }
  }

  static Map<String, int> _extract(
    String zipPath,
    List<Attachment> images,
    String mediaRoot,
    Progress report,
  ) {
    final root = Directory(mediaRoot);
    final input = InputFileStream(zipPath);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final sizes = <String, int>{};
      report(0, images.length);
      for (final (index, image) in images.indexed) {
        if (index > 0) report(index, images.length);
        final entry = archive.findFile(Bundle.imageEntry(image));
        if (entry == null) continue;
        final file = MediaStore.resolve(root, image.relPath);
        _unpack(entry, file);
        final thumb = MediaStore.resolve(root, image.thumbPath);
        final thumbEntry = archive.findFile(Bundle.thumbEntry(image));
        if (thumbEntry != null) {
          _unpack(thumbEntry, thumb);
        } else {
          thumb.parent.createSync(recursive: true);
          file.copySync(thumb.path);
        }
        sizes[image.id] = file.lengthSync();
      }
      report(images.length, images.length);
      return sizes;
    } finally {
      input.closeSync();
    }
  }

  static void _unpack(ArchiveFile entry, File to) {
    to.parent.createSync(recursive: true);
    final output = OutputFileStream(to.path);
    try {
      entry.writeContent(output);
    } finally {
      output.closeSync();
    }
  }
}
