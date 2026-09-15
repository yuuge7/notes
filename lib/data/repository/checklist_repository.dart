import 'package:drift/drift.dart';
import 'package:notes/core/util/checklist_rules.dart';
import 'package:notes/core/util/ids.dart';
import 'package:notes/core/util/sort_key.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/db/note_dao.dart';
import 'package:notes/domain/model/checklist_item.dart';
import 'package:notes/domain/model/note_type.dart';

/// Every change to a checklist's items.
///
/// Each method runs in one transaction and stamps the note itself as edited,
/// so the grid, the sync flag, and the "edited" time all treat a change to an
/// item as a change to the note.
class ChecklistRepository {
  ChecklistRepository(this._dao);

  final NoteDao _dao;

  int get _now => DateTime.now().millisecondsSinceEpoch;

  /// The note's items in order, checked and unchecked together.
  Future<List<ChecklistItem>> items(String noteId) => _dao.itemsOf(noteId);

  /// Adds an item directly after [afterItemId], or at the end of the list.
  ///
  /// Without an explicit [indent], a new item takes the indent of the item it
  /// follows, so a new line inside an indented group stays in the group.
  Future<ChecklistItem> add(
    String noteId, {
    String? afterItemId,
    String text = '',
    int? indent,
  }) => _dao.inTransaction(() async {
    final all = await _dao.itemsOf(noteId);
    final index = afterItemId == null
        ? all.length - 1
        : all.indexWhere((item) => item.id == afterItemId);
    final previous = index >= 0 ? all[index] : null;
    final next = index + 1 < all.length ? all[index + 1] : null;

    final id = newId();
    await _dao.upsertItem(
      ChecklistItemsCompanion.insert(
        id: id,
        noteId: noteId,
        sortKey: SortKey.between(previous?.sortKey ?? '', next?.sortKey ?? ''),
        updatedAtMs: _now,
        content: Value(text),
        indent: Value(
          previous == null ? 0 : (indent ?? previous.indent).clamp(0, 1),
        ),
      ),
    );
    await _dao.touchNote(noteId);
    return (await _dao.itemsOf(noteId)).firstWhere((item) => item.id == id);
  });

  Future<void> setText(String noteId, String itemId, String text) =>
      _dao.inTransaction(() async {
        await _dao.updateItem(
          itemId,
          ChecklistItemsCompanion(content: Value(text)),
        );
        await _dao.touchNote(noteId);
      });

  /// Checks or unchecks an item. A parent carries its children with it; a
  /// child changes on its own.
  Future<void> setChecked(
    String noteId,
    String itemId, {
    required bool checked,
  }) => _dao.inTransaction(() async {
    final all = await _dao.itemsOf(noteId);
    final index = all.indexWhere((item) => item.id == itemId);
    if (index < 0) return;
    for (final item in [all[index], ...ChecklistRules.childrenOf(all, index)]) {
      await _dao.updateItem(
        item.id,
        ChecklistItemsCompanion(checked: Value(checked)),
      );
    }
    await _dao.touchNote(noteId);
  });

  /// Indents an item under the open item above it, or brings it back out.
  /// The first open item has nothing to sit under and stays at the top level.
  Future<void> setIndent(String noteId, String itemId, int indent) =>
      _dao.inTransaction(() async {
        final open = ChecklistRules.open(await _dao.itemsOf(noteId));
        final index = open.indexWhere((item) => item.id == itemId);
        if (index < 0) return;
        final wanted = index == 0 ? 0 : indent.clamp(0, 1);
        if (open[index].indent == wanted) return;
        await _dao.updateItem(
          itemId,
          ChecklistItemsCompanion(indent: Value(wanted)),
        );
        await _dao.touchNote(noteId);
      });

  /// Deletes an item. An indented item left at the top of the list comes back
  /// out to the top level.
  Future<void> remove(String noteId, String itemId) =>
      _dao.inTransaction(() async {
        await _dao.deleteItem(itemId);
        await _fixIndents(noteId);
        await _dao.touchNote(noteId);
      });

  /// Joins an item onto the end of the open item above it, as backspace at the
  /// start of a line does. Returns the item that remains and where the cursor
  /// belongs in it, or null when there is no item above.
  Future<({String itemId, int cursor})?> mergeIntoPrevious(
    String noteId,
    String itemId,
  ) => _dao.inTransaction(() async {
    final open = ChecklistRules.open(await _dao.itemsOf(noteId));
    final index = open.indexWhere((item) => item.id == itemId);
    if (index <= 0) return null;

    final previous = open[index - 1];
    await _dao.updateItem(
      previous.id,
      ChecklistItemsCompanion(
        content: Value('${previous.text}${open[index].text}'),
      ),
    );
    await _dao.deleteItem(itemId);
    await _fixIndents(noteId);
    await _dao.touchNote(noteId);
    return (itemId: previous.id, cursor: previous.text.length);
  });

  /// Moves an item, with its children if it has any, so it sits after
  /// [afterItemId] and before [beforeItemId]. A null end is open. Dropping a
  /// block inside itself changes nothing.
  Future<void> move(
    String noteId,
    String itemId, {
    String? afterItemId,
    String? beforeItemId,
  }) => _dao.inTransaction(() async {
    final all = await _dao.itemsOf(noteId);
    final index = all.indexWhere((item) => item.id == itemId);
    if (index < 0) return;

    final block = [all[index], ...ChecklistRules.childrenOf(all, index)];
    final blockIds = {for (final item in block) item.id};
    if (blockIds.contains(afterItemId) || blockIds.contains(beforeItemId)) {
      return;
    }

    String keyOf(String? id) =>
        id == null ? '' : all.firstWhere((item) => item.id == id).sortKey;
    final nextKey = keyOf(beforeItemId);
    var key = keyOf(afterItemId);
    for (final item in block) {
      key = SortKey.between(key, nextKey);
      await _dao.updateItem(
        item.id,
        ChecklistItemsCompanion(sortKey: Value(key)),
      );
    }
    await _fixIndents(noteId);
    await _dao.touchNote(noteId);
  });

  Future<void> uncheckAll(String noteId) => _dao.inTransaction(() async {
    for (final item in await _dao.itemsOf(noteId)) {
      if (!item.checked) continue;
      await _dao.updateItem(
        item.id,
        const ChecklistItemsCompanion(checked: Value(false)),
      );
    }
    await _fixIndents(noteId);
    await _dao.touchNote(noteId);
  });

  Future<void> deleteChecked(String noteId) => _dao.inTransaction(() async {
    for (final item in await _dao.itemsOf(noteId)) {
      if (item.checked) await _dao.deleteItem(item.id);
    }
    await _fixIndents(noteId);
    await _dao.touchNote(noteId);
  });

  /// Deletes items that hold no text. Run when the editor closes, so the blank
  /// line left by one Enter too many does not linger in the list.
  Future<void> removeEmpty(String noteId) => _dao.inTransaction(() async {
    final empty = [
      for (final item in await _dao.itemsOf(noteId))
        if (item.text.trim().isEmpty) item,
    ];
    if (empty.isEmpty) return;
    for (final item in empty) {
      await _dao.deleteItem(item.id);
    }
    await _fixIndents(noteId);
    await _dao.touchNote(noteId);
  });

  /// Turns a text note into a checklist: each non-blank line of the body
  /// becomes an item, and the body is cleared.
  Future<void> toChecklist(String noteId) => _dao.inTransaction(() async {
    final note = await _dao.loadNote(noteId);
    if (note == null || note.isChecklist) return;

    var key = '';
    for (final entry in ChecklistRules.fromText(note.body)) {
      key = SortKey.between(key, '');
      await _dao.upsertItem(
        ChecklistItemsCompanion.insert(
          id: newId(),
          noteId: noteId,
          sortKey: key,
          updatedAtMs: _now,
          content: Value(entry.text),
          checked: Value(entry.checked),
          indent: Value(entry.indent),
        ),
      );
    }
    await _dao.updateNote(
      noteId,
      const NotesCompanion(type: Value(NoteType.checklist), body: Value('')),
    );
  });

  /// Turns a checklist into a text note: items become lines of the body, with
  /// children indented, and the items are removed. Checked state is lost.
  Future<void> toText(String noteId) => _dao.inTransaction(() async {
    final note = await _dao.loadNote(noteId);
    if (note == null || !note.isChecklist) return;

    final body = ChecklistRules.toText(note.items);
    for (final item in note.items) {
      await _dao.deleteItem(item.id);
    }
    await _dao.updateNote(
      noteId,
      NotesCompanion(type: const Value(NoteType.text), body: Value(body)),
    );
  });

  Future<void> _fixIndents(String noteId) async {
    final open = ChecklistRules.open(await _dao.itemsOf(noteId));
    for (final MapEntry(key: id, value: indent)
        in ChecklistRules.indentFixes(open).entries) {
      await _dao.updateItem(id, ChecklistItemsCompanion(indent: Value(indent)));
    }
  }
}
