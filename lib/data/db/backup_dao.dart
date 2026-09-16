import 'package:drift/drift.dart';
import 'package:notes/data/backup/import_plan.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/db/search_index.dart';
import 'package:notes/data/db/tables.dart';
import 'package:notes/data/mapper/note_mapper.dart';
import 'package:notes/domain/model/label.dart';
import 'package:notes/domain/model/note.dart';

part 'backup_dao.g.dart';

int _now() => DateTime.now().millisecondsSinceEpoch;

/// Reads everything for an export, and writes an import.
@DriftAccessor(tables: [Notes, ChecklistItems, Labels, NoteLabels, Attachments])
class BackupDao extends DatabaseAccessor<AppDatabase> with _$BackupDaoMixin {
  BackupDao(super.attachedDatabase);

  /// Every note, archived and trashed ones included, in grid order, with its
  /// items, labels, and images.
  Future<List<Note>> allNotes() async => attachedDatabase.noteDao.hydrate(
    await (select(notes)..orderBy([
          (t) => OrderingTerm(expression: t.pinned, mode: OrderingMode.desc),
          (t) => OrderingTerm(expression: t.sortKey),
        ]))
        .get(),
  );

  /// Labels that have not been deleted, in their set order.
  Future<List<Label>> liveLabels() => attachedDatabase.noteDao.allLabels();

  Future<LocalState> localState() async {
    final noteRows = await (selectOnly(
      notes,
    )..addColumns([notes.id, notes.updatedAtMs, notes.sortKey])).get();
    final imageRows =
        await (selectOnly(attachments)
              ..addColumns([attachments.id])
              ..where(attachments.deleted.equals(false)))
            .get();
    return LocalState(
      notes: {
        for (final row in noteRows)
          row.read(notes.id)!: (
            updatedAt: DateTime.fromMillisecondsSinceEpoch(
              row.read(notes.updatedAtMs)!,
            ),
            sortKey: row.read(notes.sortKey)!,
          ),
      },
      labels: [
        for (final row in await select(labels).get())
          (label: row.toDomain(), deleted: row.deleted),
      ],
      imageIds: {for (final row in imageRows) row.read(attachments.id)!},
    );
  }

  /// Runs [writes] with search indexed once at the end rather than note by
  /// note. Call it inside a transaction.
  Future<void> writeInBulk(Future<void> Function() writes) =>
      SearchIndex.bulk(customStatement, writes);

  /// Deletes every note and label for good. Items, label links, and
  /// attachments go with them through the cascade.
  Future<void> wipe() async {
    await delete(notes).go();
    await delete(labels).go();
  }

  /// Writes [labels] as they are, bringing back any that were deleted.
  Future<void> writeLabels(List<Label> labels) => batch(
    (b) => b.insertAllOnConflictUpdate(this.labels, [
      for (final label in labels)
        LabelsCompanion.insert(
          id: label.id,
          name: label.name,
          sortKey: label.sortKey,
          updatedAtMs: label.updatedAt.millisecondsSinceEpoch,
          deleted: const Value(false),
          dirty: const Value(true),
        ),
    ]),
  );

  /// Writes each note as it is: its own fields, and exactly the items,
  /// images, and labels it holds.
  ///
  /// For a note in [existing], the items, images, and labels it no longer
  /// holds are tombstoned first, as an edit would leave them. Everything is
  /// then written in one batch: an import of thousands of notes would
  /// otherwise spend its time on statements, not on data.
  ///
  /// Upserts rather than insert-or-replace: replacing deletes the row first,
  /// which would cascade away everything the note owns.
  Future<void> writeNotes(
    List<PlannedNote> planned, {
    required Set<String> existing,
  }) async {
    final now = _now();
    for (final (:note, :labelIds) in planned) {
      if (!existing.contains(note.id)) continue;
      final itemIds = [for (final item in note.items) item.id];
      await (update(checklistItems)..where(
            (t) =>
                t.noteId.equals(note.id) &
                t.deleted.equals(false) &
                t.id.isNotIn(itemIds),
          ))
          .write(
            ChecklistItemsCompanion(
              deleted: const Value(true),
              updatedAtMs: Value(now),
              dirty: const Value(true),
            ),
          );
      final imageIds = [for (final image in note.attachments) image.id];
      await (update(attachments)..where(
            (t) =>
                t.noteId.equals(note.id) &
                t.deleted.equals(false) &
                t.id.isNotIn(imageIds),
          ))
          .write(
            AttachmentsCompanion(
              deleted: const Value(true),
              updatedAtMs: Value(now),
              dirty: const Value(true),
            ),
          );
      await (update(noteLabels)..where(
            (t) =>
                t.noteId.equals(note.id) &
                t.deleted.equals(false) &
                t.labelId.isNotIn(labelIds),
          ))
          .write(
            NoteLabelsCompanion(
              deleted: const Value(true),
              updatedAtMs: Value(now),
            ),
          );
    }

    await batch((b) {
      b
        ..insertAllOnConflictUpdate(notes, [
          for (final (:note, labelIds: _) in planned)
            NotesCompanion.insert(
              id: note.id,
              type: Value(note.type),
              title: Value(note.title),
              body: Value(note.body),
              pigment: Value(note.pigment),
              pinned: Value(note.pinned),
              archived: Value(note.archived),
              sortKey: note.sortKey,
              reminderAtMs: Value(note.reminderAt?.millisecondsSinceEpoch),
              reminderRule: Value(note.reminderRule),
              reminderDone: Value(note.reminderDone),
              createdAtMs: note.createdAt.millisecondsSinceEpoch,
              updatedAtMs: note.updatedAt.millisecondsSinceEpoch,
              deleted: Value(note.deleted),
              deletedAtMs: Value(note.deletedAt?.millisecondsSinceEpoch),
              dirty: const Value(true),
            ),
        ])
        ..insertAllOnConflictUpdate(checklistItems, [
          for (final (:note, labelIds: _) in planned)
            for (final item in note.items)
              ChecklistItemsCompanion.insert(
                id: item.id,
                noteId: note.id,
                content: Value(item.text),
                checked: Value(item.checked),
                indent: Value(item.indent),
                sortKey: item.sortKey,
                updatedAtMs: item.updatedAt.millisecondsSinceEpoch,
                deleted: const Value(false),
                dirty: const Value(true),
              ),
        ])
        ..insertAllOnConflictUpdate(attachments, [
          for (final (:note, labelIds: _) in planned)
            for (final image in note.attachments)
              AttachmentsCompanion.insert(
                id: image.id,
                noteId: note.id,
                relPath: image.relPath,
                thumbPath: image.thumbPath,
                width: image.width,
                height: image.height,
                bytes: image.bytes,
                mime: Value(image.mime),
                sortKey: image.sortKey,
                createdAtMs: image.createdAt.millisecondsSinceEpoch,
                updatedAtMs: now,
                deleted: const Value(false),
                dirty: const Value(true),
              ),
        ])
        ..insertAllOnConflictUpdate(noteLabels, [
          for (final (:note, :labelIds) in planned)
            for (final labelId in labelIds)
              NoteLabelsCompanion.insert(
                noteId: note.id,
                labelId: labelId,
                updatedAtMs: now,
                deleted: const Value(false),
              ),
        ]);
    });
  }
}
