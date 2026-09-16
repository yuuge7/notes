import 'package:drift/drift.dart';
import 'package:notes/core/util/ids.dart';
import 'package:notes/core/util/sort_key.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/db/note_dao.dart';
import 'package:notes/domain/model/note.dart';
import 'package:notes/domain/model/note_type.dart';
import 'package:notes/domain/model/pigment.dart';

/// The only way the app reads or changes notes.
///
/// Widgets never see a database row: every mutation goes through here so undo,
/// sync flags, and (later) the search index stay consistent.
class NoteRepository {
  NoteRepository(this._dao);

  final NoteDao _dao;

  Stream<List<Note>> watch(Shelf shelf) => _dao.watchShelf(shelf);

  Stream<Note?> watchNote(String id) => _dao.watchNote(id);

  Future<Note?> load(String id) => _dao.loadNote(id);

  Future<int> count() => _dao.countNotes();

  /// Creates a note at the top of the grid and returns it.
  Future<Note> create({
    NoteType type = NoteType.text,
    String title = '',
    String body = '',
    Pigment pigment = Pigment.graphite,
  }) async {
    final id = newId();
    final now = DateTime.now();
    await _dao.insertNote(
      NotesCompanion.insert(
        id: id,
        sortKey: await _dao.topSortKey(),
        createdAtMs: now.millisecondsSinceEpoch,
        updatedAtMs: now.millisecondsSinceEpoch,
        type: Value(type),
        title: Value(title),
        body: Value(body),
        pigment: Value(pigment),
      ),
    );
    return (await _dao.loadNote(id))!;
  }

  Future<void> saveText(String id, {String? title, String? body}) => _dao
      .updateNote(
        id,
        NotesCompanion(
          title: title == null ? const Value.absent() : Value(title),
          body: body == null ? const Value.absent() : Value(body),
        ),
      );

  Future<void> setPinned(String id, {required bool pinned}) =>
      _dao.updateNote(id, NotesCompanion(pinned: Value(pinned)));

  Future<void> setArchived(String id, {required bool archived}) =>
      _dao.updateNote(id, NotesCompanion(archived: Value(archived)));

  Future<void> setPigment(String id, Pigment pigment) =>
      _dao.updateNote(id, NotesCompanion(pigment: Value(pigment)));

  /// Moves a note to the trash, where it stays for the retention chosen in
  /// settings.
  Future<void> delete(String id) => _dao.softDelete(id);

  Future<void> restore(String id) => _dao.restore(id);

  Future<void> emptyTrash() => _dao.emptyTrash();

  /// Deletes notes that have been in the trash longer than [retention].
  /// Called at start-up.
  Future<int> purgeExpiredTrash(Duration retention) =>
      _dao.purgeTrashedBefore(DateTime.now().subtract(retention));

  /// Makes a copy of [id] at the top of the grid: text, pigment, checklist
  /// items, and labels.
  ///
  /// Pin state and reminders stay with the original — a copy that pinned
  /// itself or fired the same alarm twice would be a surprise, not a copy.
  /// Attachments are not copied yet; their files need duplicating on disk.
  Future<Note> duplicate(String id) async {
    final source = await _dao.loadNote(id);
    if (source == null) throw StateError('Note $id does not exist');

    return _dao.inTransaction(() async {
      final copy = await create(
        type: source.type,
        title: source.title,
        body: source.body,
        pigment: source.pigment,
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final item in source.items) {
        await _dao.upsertItem(
          ChecklistItemsCompanion.insert(
            id: newId(),
            noteId: copy.id,
            sortKey: item.sortKey,
            updatedAtMs: now,
            content: Value(item.text),
            checked: Value(item.checked),
            indent: Value(item.indent),
          ),
        );
      }
      for (final label in source.labels) {
        await _dao.attachLabel(copy.id, label.id);
      }
      return (await _dao.loadNote(copy.id))!;
    });
  }

  // Bulk edits from selection mode. Each runs in one transaction.

  Future<void> setPinnedMany(Iterable<String> ids, {required bool pinned}) =>
      _dao.inTransaction(() async {
        for (final id in ids) {
          await setPinned(id, pinned: pinned);
        }
      });

  Future<void> setArchivedMany(
    Iterable<String> ids, {
    required bool archived,
  }) => _dao.inTransaction(() async {
    for (final id in ids) {
      await setArchived(id, archived: archived);
    }
  });

  Future<void> setPigmentMany(Iterable<String> ids, Pigment pigment) =>
      _dao.inTransaction(() async {
        for (final id in ids) {
          await setPigment(id, pigment);
        }
      });

  Future<void> deleteMany(Iterable<String> ids) =>
      _dao.inTransaction(() async {
        for (final id in ids) {
          await delete(id);
        }
      });

  Future<void> restoreMany(Iterable<String> ids) =>
      _dao.inTransaction(() async {
        for (final id in ids) {
          await restore(id);
        }
      });

  // Undo. A bulk recolour or pin can start from mixed values, so undo puts
  // back each note's own previous value rather than one shared value.

  Future<void> restorePigments(Map<String, Pigment> previous) =>
      _dao.inTransaction(() async {
        for (final MapEntry(key: id, value: pigment) in previous.entries) {
          await setPigment(id, pigment);
        }
      });

  Future<void> restorePinned(Map<String, bool> previous) =>
      _dao.inTransaction(() async {
        for (final MapEntry(key: id, value: pinned) in previous.entries) {
          await setPinned(id, pinned: pinned);
        }
      });

  /// Removes a trashed note for good, along with its items, label links, and
  /// attachments. Reached only from the trash, behind a confirmation.
  Future<void> deleteForever(String id) => _dao.hardDelete(id);

  /// Deletes [id] outright when it holds nothing, and reports whether it did.
  ///
  /// The editor creates a note as soon as it opens; closing it untouched
  /// should leave no trace, not an empty card or a trash entry.
  Future<bool> discardIfBlank(String id) async {
    final note = await _dao.loadNote(id);
    if (note == null || !note.isBlank) return false;
    // A note whose images were all removed is kept: the undo for the last
    // removal may still be on screen, and discarding the note would take that
    // image with it for good.
    if (await _dao.hasAnyAttachment(id)) return false;
    await _dao.hardDelete(id);
    return true;
  }

  /// Checks or unchecks one item. The note row is stamped too, so the change
  /// syncs as one edit of the note.
  Future<void> setItemChecked(
    String noteId,
    String itemId, {
    required bool checked,
  }) async {
    await _dao.updateItem(
      itemId,
      ChecklistItemsCompanion(checked: Value(checked)),
    );
    await _dao.updateNote(noteId, const NotesCompanion());
  }

  /// Places [id] between the notes with [prevKey] and [nextKey].
  ///
  /// Pass null for an open end. Writes one row: fractional keys mean the rest
  /// of the table is untouched.
  Future<void> reorder(String id, {String? prevKey, String? nextKey}) =>
      _dao.updateNote(
        id,
        NotesCompanion(sortKey: Value(SortKey.between(prevKey ?? '', nextKey ?? ''))),
      );
}
