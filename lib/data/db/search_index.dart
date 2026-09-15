/// The full-text index behind search.
///
/// One FTS5 row per note holds its title, body, list items, and label names,
/// under the note's rowid. Triggers rebuild a note's row whenever anything it
/// is made of changes, inside the same statement as the write, so no code
/// path that edits a note can leave search out of date.
///
/// Drift does not model virtual tables declared in Dart, so the table and its
/// triggers are created here with plain SQL and queried with custom selects.
abstract final class SearchIndex {
  static const table = 'notes_fts';

  /// Creates the table and its triggers, and indexes every note already in
  /// the database.
  static Future<void> install(Future<void> Function(String sql) run) async {
    await run(_createTable);
    for (final trigger in _triggers) {
      await run(trigger);
    }
    await rebuild(run);
  }

  /// Re-indexes every note from scratch.
  static Future<void> rebuild(Future<void> Function(String sql) run) async {
    await run('DELETE FROM notes_fts');
    await run(_insertFor('1'));
  }

  // unicode61 with diacritics removed, so "cafe" finds "café" and "sosea"
  // finds "șosea". Prefix indexes for one to three characters keep searching
  // as you type fast while the query is still short.
  static const _createTable = '''
CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
  title, body, items, labels,
  tokenize = 'unicode61 remove_diacritics 2',
  prefix = '1 2 3'
)''';

  /// Removes, then rebuilds, the index rows of the notes matching [where],
  /// a condition on `notes n`.
  static String _reindex(String where) =>
      'DELETE FROM notes_fts WHERE rowid IN '
      '(SELECT n.rowid FROM notes n WHERE $where); '
      '${_insertFor(where)};';

  static String _insertFor(String where) => '''
INSERT INTO notes_fts (rowid, title, body, items, labels)
SELECT
  n.rowid,
  n.title,
  n.body,
  coalesce((
    SELECT group_concat(c."text", char(10)) FROM checklist_items c
    WHERE c.note_id = n.id AND c.deleted = 0
  ), ''),
  coalesce((
    SELECT group_concat(l.name, char(10)) FROM note_labels nl
    JOIN labels l ON l.id = nl.label_id
    WHERE nl.note_id = n.id AND nl.deleted = 0 AND l.deleted = 0
  ), '')
FROM notes n
WHERE $where''';

  static String _trigger(String name, String event, String body) =>
      'CREATE TRIGGER IF NOT EXISTS $name $event BEGIN $body END';

  // Updates only re-index when a column that is searched changes: moving,
  // pinning, or recolouring a note leaves the index alone.
  static final List<String> _triggers = [
    _trigger(
      'notes_fts_note_insert',
      'AFTER INSERT ON notes',
      _reindex('n.id = NEW.id'),
    ),
    _trigger(
      'notes_fts_note_update',
      'AFTER UPDATE OF title, body ON notes',
      _reindex('n.id = NEW.id'),
    ),
    _trigger(
      'notes_fts_note_delete',
      'AFTER DELETE ON notes',
      'DELETE FROM notes_fts WHERE rowid = OLD.rowid;',
    ),
    _trigger(
      'notes_fts_item_insert',
      'AFTER INSERT ON checklist_items',
      _reindex('n.id = NEW.note_id'),
    ),
    _trigger(
      'notes_fts_item_update',
      'AFTER UPDATE OF "text", deleted ON checklist_items',
      _reindex('n.id = NEW.note_id'),
    ),
    _trigger(
      'notes_fts_item_delete',
      'AFTER DELETE ON checklist_items',
      _reindex('n.id = OLD.note_id'),
    ),
    _trigger(
      'notes_fts_link_insert',
      'AFTER INSERT ON note_labels',
      _reindex('n.id = NEW.note_id'),
    ),
    _trigger(
      'notes_fts_link_update',
      'AFTER UPDATE OF deleted ON note_labels',
      _reindex('n.id = NEW.note_id'),
    ),
    _trigger(
      'notes_fts_link_delete',
      'AFTER DELETE ON note_labels',
      _reindex('n.id = OLD.note_id'),
    ),
    // A renamed or deleted label changes the text of every note wearing it.
    _trigger(
      'notes_fts_label_update',
      'AFTER UPDATE OF name, deleted ON labels',
      _reindex(
        'n.id IN (SELECT note_id FROM note_labels WHERE label_id = NEW.id)',
      ),
    ),
  ];
}
