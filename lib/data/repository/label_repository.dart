import 'package:drift/drift.dart';
import 'package:notes/core/util/ids.dart';
import 'package:notes/core/util/sort_key.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/db/note_dao.dart';
import 'package:notes/domain/model/label.dart';
import 'package:notes/domain/model/note.dart';
import 'package:notes/domain/model/note_page.dart';

/// How a rename went.
enum RenameResult {
  renamed,

  /// The name was already this, or the label is gone.
  unchanged,

  /// Nothing but spaces was typed.
  empty,

  /// Another label already has the name, ignoring case.
  taken,
}

/// A deleted label and the notes it was taken off, for undo.
typedef DeletedLabel = ({String labelId, List<String> noteIds});

/// Every change to labels and to which notes wear them.
class LabelRepository {
  LabelRepository(this._dao);

  final NoteDao _dao;

  /// Longest label name, in characters. A label is a word or two on a chip.
  static const maxLength = 50;

  int get _now => DateTime.now().millisecondsSinceEpoch;

  Stream<List<Label>> watchAll() => _dao.watchLabels();

  Future<List<Label>> all() => _dao.allLabels();

  /// Notes on the grid, not archived or trashed, that wear [labelId].
  Stream<List<Note>> watchNotes(String labelId) =>
      _dao.watchLabelShelf(labelId);

  /// The first [limit] of those notes, and how many there are.
  Stream<NotePage> watchNotesPage(String labelId, int limit) =>
      _dao.watchLabelShelfPage(labelId, limit);

  /// How many of [noteIds] wear each label, by label id.
  Stream<Map<String, int>> watchUsage(List<String> noteIds) =>
      _dao.watchLabelUsage(noteIds);

  /// [raw] tidied into a label name: trimmed, runs of spaces made one, and
  /// cut to [maxLength]. Null when nothing is left.
  static String? cleanName(String raw) {
    final name = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) return null;
    return name.length <= maxLength
        ? name
        : name.substring(0, maxLength).trimRight();
  }

  /// The label called [name], ignoring case. One is made at the end of the
  /// list when there is none, so typing an existing name never duplicates it.
  Future<Label> create(String name) => _dao.inTransaction(() async {
    final clean = cleanName(name);
    if (clean == null) throw ArgumentError.value(name, 'name', 'is blank');

    final existing = await _dao.liveLabelNamed(clean);
    if (existing != null) return existing;

    final last = await _dao.lastLabelSortKey();
    final id = newId();
    await _dao.upsertLabel(
      LabelsCompanion.insert(
        id: id,
        name: clean,
        sortKey: last == null ? SortKey.first : SortKey.after(last),
        updatedAtMs: _now,
      ),
    );
    return (await _dao.loadLabel(id))!;
  });

  Future<RenameResult> rename(String id, String name) =>
      _dao.inTransaction(() async {
        final clean = cleanName(name);
        if (clean == null) return RenameResult.empty;
        final label = await _dao.loadLabel(id);
        if (label == null || label.name == clean) return RenameResult.unchanged;

        final other = await _dao.liveLabelNamed(clean);
        if (other != null && other.id != id) return RenameResult.taken;

        await _dao.updateLabel(id, LabelsCompanion(name: Value(clean)));
        return RenameResult.renamed;
      });

  /// Deletes a label and takes it off every note. The notes stay.
  Future<DeletedLabel> delete(String id) => _dao.inTransaction(
    () async => (labelId: id, noteIds: await _dao.tombstoneLabel(id)),
  );

  /// Undoes [delete]. When a label with the same name was made in the
  /// meantime, the notes get that label back instead of a second copy.
  Future<void> restore(DeletedLabel deleted) => _dao.inTransaction(() async {
    final label = await _dao.loadLabel(deleted.labelId, includeDeleted: true);
    if (label == null) return;

    final twin = await _dao.liveLabelNamed(label.name);
    final labelId = twin?.id ?? deleted.labelId;
    if (twin == null) await _dao.reviveLabel(deleted.labelId);
    for (final noteId in deleted.noteIds) {
      await _dao.attachLabel(noteId, labelId);
    }
  });

  /// Places [id] between the labels with [prevKey] and [nextKey]; null is an
  /// open end.
  Future<void> reorder(String id, {String? prevKey, String? nextKey}) =>
      _dao.updateLabel(
        id,
        LabelsCompanion(
          sortKey: Value(SortKey.between(prevKey ?? '', nextKey ?? '')),
        ),
      );

  /// Puts [labelId] on every note in [noteIds], or takes it off. Each note is
  /// stamped as edited. A label deleted meanwhile, as under a note begun on
  /// its page or from its home screen widget, goes on nothing.
  Future<void> setOnNotes(
    Iterable<String> noteIds,
    String labelId, {
    required bool on,
  }) => _dao.inTransaction(() async {
    if (on && await _dao.loadLabel(labelId) == null) return;
    for (final noteId in noteIds) {
      if (on) {
        await _dao.attachLabel(noteId, labelId);
      } else {
        await _dao.detachLabel(noteId, labelId);
      }
      await _dao.touchNote(noteId);
    }
  });
}
