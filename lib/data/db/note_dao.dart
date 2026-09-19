import 'dart:async';

import 'package:drift/drift.dart';
import 'package:notes/core/util/sort_key.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/db/tables.dart';
import 'package:notes/data/mapper/note_mapper.dart';
import 'package:notes/domain/model/attachment.dart';
import 'package:notes/domain/model/checklist_item.dart';
import 'package:notes/domain/model/label.dart';
import 'package:notes/domain/model/note.dart';
import 'package:notes/domain/model/note_page.dart';

part 'note_dao.g.dart';

/// Which shelf of notes a query targets.
enum Shelf { active, archived, trash }

/// Every set of notes a home screen widget can be showing, each as the first
/// notes of its page: the grid, the pinned notes, and each label's page.
typedef WidgetShelves = ({
  NotePage all,
  NotePage pinned,
  List<({Label label, NotePage page})> labels,
});

int _now() => DateTime.now().millisecondsSinceEpoch;

@DriftAccessor(tables: [Notes, ChecklistItems, Labels, NoteLabels, Attachments])
class NoteDao extends DatabaseAccessor<AppDatabase> with _$NoteDaoMixin {
  NoteDao(super.attachedDatabase);

  /// Emits the shelf now, and again whenever anything a note is made of
  /// changes.
  Stream<List<Note>> watchShelf(Shelf shelf) =>
      reloadOnChange(() => loadShelf(shelf));

  Stream<Note?> watchNote(String id) => reloadOnChange(() => loadNote(id));

  /// Runs [load] on listen and again after every write to a table a note is
  /// assembled from.
  ///
  /// A note spans five tables, so watching only `notes` would miss a checked
  /// item or a removed label. Two details matter here:
  ///
  /// * Cancelling stops listening at once. An `async*` generator parked in
  ///   `await for` would only notice the cancel at the next database write,
  ///   leaving a live listener behind every closed screen until then.
  /// * When writes land back to back, only the newest reload is delivered, so
  ///   a slow earlier read can never overwrite a fresher one.
  Stream<T> reloadOnChange<T>(Future<T> Function() load) {
    StreamSubscription<Set<TableUpdate>>? updates;
    var generation = 0;
    late final StreamController<T> controller;

    Future<void> reload() async {
      final token = ++generation;
      try {
        final value = await load();
        if (token == generation && !controller.isClosed) {
          controller.add(value);
        }
      } on Object catch (error, stackTrace) {
        if (!controller.isClosed) controller.addError(error, stackTrace);
      }
    }

    controller = StreamController<T>(
      onListen: () {
        updates = attachedDatabase
            .tableUpdates(
              TableUpdateQuery.onAllTables([
                notes,
                checklistItems,
                labels,
                noteLabels,
                attachments,
              ]),
            )
            .listen((_) => unawaited(reload()));
        unawaited(reload());
      },
      onCancel: () => updates?.cancel(),
    );
    return controller.stream;
  }

  Future<List<Note>> loadShelf(Shelf shelf) async =>
      hydrate(await _shelfQuery(shelf).get());

  /// The first [limit] notes of [shelf], reloaded after every change.
  Stream<NotePage> watchShelfPage(Shelf shelf, int limit) =>
      reloadOnChange(() => loadShelfPage(shelf, limit));

  Future<NotePage> loadShelfPage(Shelf shelf, int limit) async =>
      _page(_shelfQuery(shelf), limit, await _count(_onShelf(notes, shelf)));

  /// How many notes match [where].
  Future<int> _count(Expression<bool> where) async {
    final count = notes.id.count();
    final row =
        await (selectOnly(notes)
              ..addColumns([count])
              ..where(where))
            .getSingle();
    return row.read(count) ?? 0;
  }

  /// Loads one row past [limit], to know where the next page starts.
  Future<NotePage> _page(
    SimpleSelectStatement<$NotesTable, NoteRow> query,
    int limit,
    int total,
  ) async {
    final rows = await (query..limit(limit + 1)).get();
    final next = rows.length > limit ? rows[limit] : null;
    return NotePage(
      notes: await hydrate(rows.take(limit).toList()),
      total: total,
      after: next == null ? null : (sortKey: next.sortKey, pinned: next.pinned),
    );
  }

  static Expression<bool> _onShelf($NotesTable t, Shelf shelf) =>
      switch (shelf) {
        Shelf.active => t.deleted.equals(false) & t.archived.equals(false),
        Shelf.archived => t.deleted.equals(false) & t.archived.equals(true),
        Shelf.trash => t.deleted.equals(true),
      };

  SimpleSelectStatement<$NotesTable, NoteRow> _shelfQuery(Shelf shelf) {
    final query = select(notes)..where((t) => _onShelf(t, shelf));

    // Pinned notes float; everything else follows the manual order, which
    // starts out as newest-captured-first.
    if (shelf == Shelf.trash) {
      query.orderBy([
        (t) => OrderingTerm(expression: t.deletedAtMs, mode: OrderingMode.desc),
      ]);
    } else {
      query.orderBy([
        (t) => OrderingTerm(expression: t.pinned, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.sortKey),
      ]);
    }
    return query;
  }

  Future<Note?> loadNote(String id) async {
    final row = await (select(
      notes,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return (await hydrate([row])).firstOrNull;
  }

  /// Loads items, labels, and attachments for [rows] in three queries rather
  /// than three per note.
  Future<List<Note>> hydrate(List<NoteRow> rows) async {
    if (rows.isEmpty) return const [];
    final ids = rows.map((row) => row.id).toList();

    final itemRows =
        await (select(checklistItems)
              ..where((t) => t.noteId.isIn(ids) & t.deleted.equals(false))
              ..orderBy([(t) => OrderingTerm(expression: t.sortKey)]))
            .get();

    final attachmentRows =
        await (select(attachments)
              ..where((t) => t.noteId.isIn(ids) & t.deleted.equals(false))
              ..orderBy([(t) => OrderingTerm(expression: t.sortKey)]))
            .get();

    final labelJoin =
        select(noteLabels).join([
            innerJoin(labels, labels.id.equalsExp(noteLabels.labelId)),
          ])
          ..where(
            noteLabels.noteId.isIn(ids) &
                noteLabels.deleted.equals(false) &
                labels.deleted.equals(false),
          )
          ..orderBy([OrderingTerm(expression: labels.sortKey)]);
    final labelRows = await labelJoin.get();

    final itemsByNote = <String, List<ChecklistItem>>{};
    for (final row in itemRows) {
      (itemsByNote[row.noteId] ??= []).add(row.toDomain());
    }
    final attachmentsByNote = <String, List<Attachment>>{};
    for (final row in attachmentRows) {
      (attachmentsByNote[row.noteId] ??= []).add(row.toDomain());
    }
    final labelsByNote = <String, List<Label>>{};
    for (final row in labelRows) {
      final link = row.readTable(noteLabels);
      (labelsByNote[link.noteId] ??= []).add(row.readTable(labels).toDomain());
    }

    return [
      for (final row in rows)
        row.toDomain(
          items: itemsByNote[row.id] ?? const [],
          labels: labelsByNote[row.id] ?? const [],
          attachments: attachmentsByNote[row.id] ?? const [],
        ),
    ];
  }

  /// A sort key that places a note above every other note.
  Future<String> topSortKey() async {
    final row =
        await (selectOnly(notes)
              ..addColumns([notes.sortKey])
              ..where(notes.deleted.equals(false))
              ..orderBy([OrderingTerm(expression: notes.sortKey)])
              ..limit(1))
            .getSingleOrNull();
    final lowest = row?.read(notes.sortKey);
    return lowest == null ? SortKey.first : SortKey.before(lowest);
  }

  // A plain insert, never insert-or-replace: replacing a row deletes it
  // first, which would cascade away its items and labels.
  Future<void> insertNote(NotesCompanion entry) => into(notes).insert(entry);

  /// Applies [patch] and stamps the row as changed.
  Future<void> updateNote(String id, NotesCompanion patch) async {
    await (update(notes)..where((t) => t.id.equals(id))).write(
      patch.copyWith(updatedAtMs: Value(_now()), dirty: const Value(true)),
    );
  }

  Future<void> softDelete(String id) async {
    final now = _now();
    await (update(notes)..where((t) => t.id.equals(id))).write(
      NotesCompanion(
        deleted: const Value(true),
        deletedAtMs: Value(now),
        updatedAtMs: Value(now),
        dirty: const Value(true),
      ),
    );
  }

  Future<void> restore(String id) => updateNote(
    id,
    const NotesCompanion(deleted: Value(false), deletedAtMs: Value(null)),
  );

  /// Removes trashed notes whose stay has expired. Rows are gone for good
  /// here, along with their items and attachments via cascade.
  Future<int> purgeTrashedBefore(DateTime cutoff) {
    final ms = cutoff.millisecondsSinceEpoch;
    return (delete(notes)..where(
          (t) => t.deleted.equals(true) & t.deletedAtMs.isSmallerThanValue(ms),
        ))
        .go();
  }

  Future<int> emptyTrash() =>
      (delete(notes)..where((t) => t.deleted.equals(true))).go();

  Future<int> countNotes() async {
    final count = notes.id.count();
    final row = await (selectOnly(notes)..addColumns([count])).getSingle();
    return row.read(count) ?? 0;
  }

  /// Removes a note outright, skipping the trash. Only for a note that never
  /// held anything, such as a blank capture abandoned in the editor.
  Future<void> hardDelete(String id) =>
      (delete(notes)..where((t) => t.id.equals(id))).go();

  /// Runs [action] atomically, so a bulk edit that fails halfway leaves no
  /// half-applied change behind.
  Future<T> inTransaction<T>(Future<T> Function() action) =>
      transaction(action);

  // Checklist items ---------------------------------------------------------

  Future<void> upsertItem(ChecklistItemsCompanion entry) =>
      into(checklistItems).insertOnConflictUpdate(entry);

  Future<void> upsertItems(List<ChecklistItemsCompanion> entries) =>
      batch((b) => b.insertAllOnConflictUpdate(checklistItems, entries));

  /// Applies [patch] to one item and stamps the row as changed.
  Future<void> updateItem(String id, ChecklistItemsCompanion patch) async {
    await (update(checklistItems)..where((t) => t.id.equals(id))).write(
      patch.copyWith(updatedAtMs: Value(_now()), dirty: const Value(true)),
    );
  }

  Future<void> deleteItem(String id) async {
    await (update(checklistItems)..where((t) => t.id.equals(id))).write(
      ChecklistItemsCompanion(
        deleted: const Value(true),
        updatedAtMs: Value(_now()),
        dirty: const Value(true),
      ),
    );
  }

  /// The note's items that are not deleted, in sort-key order.
  Future<List<ChecklistItem>> itemsOf(String noteId) async {
    final rows =
        await (select(checklistItems)
              ..where((t) => t.noteId.equals(noteId) & t.deleted.equals(false))
              ..orderBy([(t) => OrderingTerm(expression: t.sortKey)]))
            .get();
    return rows.map((row) => row.toDomain()).toList();
  }

  /// Stamps the note as changed without altering its own fields, for edits
  /// made to its items.
  Future<void> touchNote(String noteId) =>
      updateNote(noteId, const NotesCompanion());

  // Attachments -------------------------------------------------------------

  Future<void> insertAttachment(AttachmentsCompanion entry) =>
      into(attachments).insert(entry);

  /// The attachments of [noteId] that have not been removed, in order.
  Future<List<Attachment>> attachmentsOf(String noteId) async {
    final rows =
        await (select(attachments)
              ..where((t) => t.noteId.equals(noteId) & t.deleted.equals(false))
              ..orderBy([(t) => OrderingTerm(expression: t.sortKey)]))
            .get();
    return [for (final row in rows) row.toDomain()];
  }

  Future<String?> lastAttachmentSortKey(String noteId) async {
    final row =
        await (selectOnly(attachments)
              ..addColumns([attachments.sortKey])
              ..where(
                attachments.noteId.equals(noteId) &
                    attachments.deleted.equals(false),
              )
              ..orderBy([OrderingTerm.desc(attachments.sortKey)])
              ..limit(1))
            .getSingleOrNull();
    return row?.read(attachments.sortKey);
  }

  /// Removes or restores one attachment, stamping it and its note as changed.
  Future<void> setAttachmentDeleted(String id, {required bool deleted}) async {
    final row = await (select(
      attachments,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    await (update(attachments)..where((t) => t.id.equals(id))).write(
      AttachmentsCompanion(
        deleted: Value(deleted),
        updatedAtMs: Value(_now()),
        dirty: const Value(true),
      ),
    );
    await touchNote(row.noteId);
  }

  /// Whether [noteId] has ever held an image, removed ones included.
  Future<bool> hasAnyAttachment(String noteId) async {
    final row =
        await (selectOnly(attachments)
              ..addColumns([attachments.id])
              ..where(attachments.noteId.equals(noteId))
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  /// Every attachment row, removed ones included, for finding the files
  /// nothing refers to.
  Future<List<AttachmentRow>> allAttachmentRows() => select(attachments).get();

  /// Fires after any write to the attachments table, including the rows a
  /// note takes with it when it is deleted for good.
  Stream<void> watchAttachmentWrites() => attachedDatabase
      .tableUpdates(TableUpdateQuery.onAllTables([attachments]))
      .map((_) {});

  // Reminders ---------------------------------------------------------------

  /// Every note outside the trash that has a reminder, soonest first, each
  /// with its row id. Notifications are numbered by that id: Android wants an
  /// int, and the row id is one the note already owns.
  Future<List<(int, Note)>> loadReminders() async {
    final rows = await customSelect(
      'SELECT rowid AS notification_id, * FROM notes '
      'WHERE deleted = 0 AND reminder_at_ms IS NOT NULL '
      'ORDER BY reminder_at_ms',
      readsFrom: {notes},
    ).get();
    final hydrated = await hydrate([
      for (final row in rows) notes.map(row.data),
    ]);
    return [
      for (final (index, note) in hydrated.indexed)
        (rows[index].read<int>('notification_id'), note),
    ];
  }

  Stream<List<(int, Note)>> watchReminders() => reloadOnChange(loadReminders);

  // Labels ------------------------------------------------------------------

  Future<void> upsertLabel(LabelsCompanion entry) =>
      into(labels).insertOnConflictUpdate(entry);

  /// Puts a label on a note, bringing back a link that was removed before.
  Future<void> attachLabel(String noteId, String labelId) =>
      into(noteLabels).insertOnConflictUpdate(
        NoteLabelsCompanion.insert(
          noteId: noteId,
          labelId: labelId,
          updatedAtMs: _now(),
          deleted: const Value(false),
        ),
      );

  Future<void> detachLabel(String noteId, String labelId) async {
    await (update(noteLabels)..where(
      (t) => t.noteId.equals(noteId) & t.labelId.equals(labelId),
    )).write(
      NoteLabelsCompanion(
        deleted: const Value(true),
        updatedAtMs: Value(_now()),
      ),
    );
  }

  Stream<List<Label>> watchLabels() => _liveLabels().watch().map(
    (rows) => [for (final row in rows) row.toDomain()],
  );

  Future<List<Label>> allLabels() async => [
    for (final row in await _liveLabels().get()) row.toDomain(),
  ];

  SimpleSelectStatement<$LabelsTable, LabelRow> _liveLabels() =>
      select(labels)
        ..where((t) => t.deleted.equals(false))
        ..orderBy([(t) => OrderingTerm(expression: t.sortKey)]);

  /// The label with [id]. A deleted label only with [includeDeleted].
  Future<Label?> loadLabel(String id, {bool includeDeleted = false}) async {
    final query = select(labels)..where((t) => t.id.equals(id));
    if (!includeDeleted) query.where((t) => t.deleted.equals(false));
    return (await query.getSingleOrNull())?.toDomain();
  }

  /// The live label called [name], ignoring case the way the unique index
  /// does.
  Future<Label?> liveLabelNamed(String name) async {
    final row = await customSelect(
      'SELECT * FROM labels '
      'WHERE deleted = 0 AND name = ? COLLATE NOCASE LIMIT 1',
      variables: [Variable.withString(name)],
      readsFrom: {labels},
    ).getSingleOrNull();
    return row == null ? null : labels.map(row.data).toDomain();
  }

  Future<String?> lastLabelSortKey() async {
    final row =
        await (selectOnly(labels)
              ..addColumns([labels.sortKey])
              ..where(labels.deleted.equals(false))
              ..orderBy([OrderingTerm.desc(labels.sortKey)])
              ..limit(1))
            .getSingleOrNull();
    return row?.read(labels.sortKey);
  }

  /// Applies [patch] to one label and stamps the row as changed.
  Future<void> updateLabel(String id, LabelsCompanion patch) async {
    await (update(labels)..where((t) => t.id.equals(id))).write(
      patch.copyWith(updatedAtMs: Value(_now()), dirty: const Value(true)),
    );
  }

  /// Marks a label deleted and takes it off its notes. Returns the ids of the
  /// notes it was on.
  Future<List<String>> tombstoneLabel(String id) async {
    final live =
        noteLabels.labelId.equals(id) & noteLabels.deleted.equals(false);
    final links = await (select(noteLabels)..where((_) => live)).get();
    await (update(noteLabels)..where((_) => live)).write(
      NoteLabelsCompanion(
        deleted: const Value(true),
        updatedAtMs: Value(_now()),
      ),
    );
    await updateLabel(id, const LabelsCompanion(deleted: Value(true)));
    return [for (final link in links) link.noteId];
  }

  Future<void> reviveLabel(String id) =>
      updateLabel(id, const LabelsCompanion(deleted: Value(false)));

  /// Notes on the grid — not archived, not trashed — that wear [labelId].
  Stream<List<Note>> watchLabelShelf(String labelId) =>
      reloadOnChange(() => loadLabelShelf(labelId));

  Future<List<Note>> loadLabelShelf(String labelId) async =>
      hydrate(await _labelShelfQuery(labelId).get());

  /// The first [limit] notes on the grid wearing [labelId], reloaded after
  /// every change.
  Stream<NotePage> watchLabelShelfPage(String labelId, int limit) =>
      reloadOnChange(() => loadLabelShelfPage(labelId, limit));

  Future<NotePage> loadLabelShelfPage(String labelId, int limit) async => _page(
    _labelShelfQuery(labelId),
    limit,
    await _count(_wearing(notes, labelId)),
  );

  Expression<bool> _wearing($NotesTable t, String labelId) {
    final wearing = selectOnly(noteLabels)
      ..addColumns([noteLabels.noteId])
      ..where(
        noteLabels.labelId.equals(labelId) & noteLabels.deleted.equals(false),
      );
    return t.deleted.equals(false) &
        t.archived.equals(false) &
        t.id.isInQuery(wearing);
  }

  SimpleSelectStatement<$NotesTable, NoteRow> _labelShelfQuery(
    String labelId,
  ) => select(notes)
    ..where((t) => _wearing(t, labelId))
    ..orderBy([
      (t) => OrderingTerm(expression: t.pinned, mode: OrderingMode.desc),
      (t) => OrderingTerm(expression: t.sortKey),
    ]);

  /// The first [limit] notes of every widget shelf, reloaded after every
  /// change.
  Stream<WidgetShelves> watchWidgetShelves(int limit) =>
      reloadOnChange(() => loadWidgetShelves(limit));

  /// Loads the widget shelves together. A note on several of them, pinned
  /// and wearing two labels, is read once. The pinned notes are the grid's
  /// first rows: the grid puts them first, to the same limit.
  Future<WidgetShelves> loadWidgetShelves(int limit) async {
    final grid = await (_shelfQuery(Shelf.active)..limit(limit)).get();
    final pinned = [
      for (final row in grid)
        if (row.pinned) row,
    ];
    Future<({Label label, List<NoteRow> rows, int total})> shelf(
      Label label,
    ) async => (
      label: label,
      rows: await (_labelShelfQuery(label.id)..limit(limit)).get(),
      total: await _count(_wearing(notes, label.id)),
    );
    final labelShelves = await Future.wait((await allLabels()).map(shelf));

    final rows = {
      for (final row in [
        ...grid,
        for (final shelf in labelShelves) ...shelf.rows,
      ])
        row.id: row,
    };
    final hydrated = {
      for (final note in await hydrate(rows.values.toList())) note.id: note,
    };
    NotePage page(List<NoteRow> rows, int total) => NotePage(
      notes: [for (final row in rows) hydrated[row.id]!],
      total: total,
    );

    final active = _onShelf(notes, Shelf.active);
    return (
      all: page(grid, await _count(active)),
      pinned: page(pinned, await _count(active & notes.pinned.equals(true))),
      labels: [
        for (final shelf in labelShelves)
          (label: shelf.label, page: page(shelf.rows, shelf.total)),
      ],
    );
  }

  /// How many of [noteIds] wear each label, by label id.
  Stream<Map<String, int>> watchLabelUsage(List<String> noteIds) =>
      reloadOnChange(() async {
        final count = noteLabels.noteId.count();
        final rows =
            await (selectOnly(noteLabels)
                  ..addColumns([noteLabels.labelId, count])
                  ..where(
                    noteLabels.noteId.isIn(noteIds) &
                        noteLabels.deleted.equals(false),
                  )
                  ..groupBy([noteLabels.labelId]))
                .get();
        return {
          for (final row in rows) row.read(noteLabels.labelId)!: row.read(count)!,
        };
      });
}
