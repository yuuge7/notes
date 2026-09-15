import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:notes/core/util/ids.dart';
import 'package:notes/core/util/sort_key.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/db/note_dao.dart';
import 'package:notes/data/media/image_processor.dart';
import 'package:notes/data/media/media_store.dart';
import 'package:notes/domain/model/attachment.dart';

/// How adding a batch of photos went.
typedef AddedImages = ({int added, int failed});

/// Images on notes: adding them, taking them off, copying them with a note,
/// and clearing away files that nothing refers to any more.
class AttachmentRepository {
  AttachmentRepository(this._dao, this._store, this._processor);

  final NoteDao _dao;
  final MediaStore _store;
  final ImageProcessor _processor;

  /// Files being written for attachments not in the database yet. A sweep
  /// running meanwhile leaves them alone.
  final _writing = <String>{};

  /// The batch of photos being added, which the next batch waits for.
  Future<void> _batches = Future.value();

  Future<List<Attachment>> of(String noteId) => _dao.attachmentsOf(noteId);

  /// Adds [sources] after the images [noteId] already has, each compressed
  /// into the app's own storage. The picked files themselves are left alone.
  ///
  /// A photo that cannot be read is skipped and counted as failed; the rest
  /// still go in. Batches run one after another, so a batch started while
  /// another is still compressing goes after it rather than among it.
  Future<AddedImages> addImages(String noteId, List<File> sources) {
    final run = _batches.then((_) => _add(noteId, sources));
    _batches = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<AddedImages> _add(String noteId, List<File> sources) async {
    var after = await _dao.lastAttachmentSortKey(noteId);
    var added = 0;
    var failed = 0;
    for (final source in sources) {
      final id = newId();
      final paths = (
        image: MediaStore.imagePathFor(id),
        thumb: MediaStore.thumbPathFor(id),
      );
      _writing.addAll([paths.image, paths.thumb]);
      try {
        final processed = await _processor.process(
          source,
          image: await _store.prepare(paths.image),
          thumb: await _store.prepare(paths.thumb),
        );
        final sortKey = after == null ? SortKey.first : SortKey.after(after);
        final now = DateTime.now().millisecondsSinceEpoch;
        await _dao.insertAttachment(
          AttachmentsCompanion.insert(
            id: id,
            noteId: noteId,
            relPath: paths.image,
            thumbPath: paths.thumb,
            width: processed.width,
            height: processed.height,
            bytes: processed.bytes,
            sortKey: sortKey,
            createdAtMs: now,
            updatedAtMs: now,
          ),
        );
        after = sortKey;
        added++;
      } on Object catch (error) {
        debugPrint('A photo was not added: $error');
        failed++;
        await _store.delete([paths.image, paths.thumb]);
      } finally {
        _writing.removeAll([paths.image, paths.thumb]);
      }
    }
    if (added > 0) await _dao.touchNote(noteId);
    return (added: added, failed: failed);
  }

  /// Takes an image off its note. The row stays as a tombstone and the files
  /// stay on disk, so [restore] can put it back; the sweep at start-up clears
  /// the files.
  Future<void> remove(String attachmentId) =>
      _dao.setAttachmentDeleted(attachmentId, deleted: true);

  Future<void> restore(String attachmentId) =>
      _dao.setAttachmentDeleted(attachmentId, deleted: false);

  /// Gives the note [to] its own copies of the images on [from], for Make a
  /// copy. Deleting either note later leaves the other's images whole.
  Future<void> copyAll({required String from, required String to}) async {
    final images = await _dao.attachmentsOf(from);
    if (images.isEmpty) return;
    for (final image in images) {
      final id = newId();
      final paths = (
        image: MediaStore.imagePathFor(id),
        thumb: MediaStore.thumbPathFor(id),
      );
      _writing.addAll([paths.image, paths.thumb]);
      try {
        await (await _store.file(
          image.relPath,
        )).copy((await _store.prepare(paths.image)).path);
        await (await _store.file(
          image.thumbPath,
        )).copy((await _store.prepare(paths.thumb)).path);
        final now = DateTime.now().millisecondsSinceEpoch;
        await _dao.insertAttachment(
          AttachmentsCompanion.insert(
            id: id,
            noteId: to,
            relPath: paths.image,
            thumbPath: paths.thumb,
            width: image.width,
            height: image.height,
            bytes: image.bytes,
            mime: Value(image.mime),
            sortKey: image.sortKey,
            createdAtMs: now,
            updatedAtMs: now,
          ),
        );
      } on FileSystemException catch (error) {
        // The original's file is missing: the copy goes without that image.
        debugPrint('An image was not copied: $error');
        await _store.delete([paths.image, paths.thumb]);
      } finally {
        _writing.removeAll([paths.image, paths.thumb]);
      }
    }
    await _dao.touchNote(to);
  }

  /// Deletes image files that no attachment refers to, and returns how many
  /// went.
  ///
  /// The files of removed attachments stay unless [dropRemoved] is set, since
  /// the undo for a removal may still be on screen. At start-up no undo can
  /// be waiting, and the sweep then clears those too. A note in the trash
  /// keeps its images: it can still be restored.
  Future<int> sweep({required bool dropRemoved}) async {
    final onDisk = await _store.listAll();
    // Read after listing, so a file written in the meantime is either on the
    // list of files being written or not on the disk listing at all.
    final keep = <String>{..._writing};
    for (final row in await _dao.allAttachmentRows()) {
      if (dropRemoved && row.deleted) continue;
      keep
        ..add(row.relPath)
        ..add(row.thumbPath);
    }
    keep.addAll(_writing);
    final orphans = [
      for (final path in onDisk)
        if (!keep.contains(path)) path,
    ];
    await _store.delete(orphans);
    return orphans.length;
  }
}
