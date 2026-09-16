/// The database as schema version 2 created it, taken from `sqlite_master`
/// of a fresh version 2 database, less the tables FTS5 makes for itself.
/// Migration tests build this by hand and let the current app upgrade it,
/// as an install from before settings would be upgraded on a phone.
const schemaV2 = [
  'CREATE TABLE "notes" ("updated_at_ms" INTEGER NOT NULL, "deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("deleted" IN (0, 1)), "dirty" INTEGER NOT NULL DEFAULT 1 CHECK ("dirty" IN (0, 1)), "id" TEXT NOT NULL, "type" TEXT NOT NULL DEFAULT \'text\', "title" TEXT NOT NULL DEFAULT \'\', "body" TEXT NOT NULL DEFAULT \'\', "pigment" TEXT NOT NULL DEFAULT \'graphite\', "pinned" INTEGER NOT NULL DEFAULT 0 CHECK ("pinned" IN (0, 1)), "archived" INTEGER NOT NULL DEFAULT 0 CHECK ("archived" IN (0, 1)), "sort_key" TEXT NOT NULL, "reminder_at_ms" INTEGER NULL, "reminder_rule" TEXT NULL, "reminder_done" INTEGER NOT NULL DEFAULT 0 CHECK ("reminder_done" IN (0, 1)), "created_at_ms" INTEGER NOT NULL, "deleted_at_ms" INTEGER NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "checklist_items" ("updated_at_ms" INTEGER NOT NULL, "deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("deleted" IN (0, 1)), "dirty" INTEGER NOT NULL DEFAULT 1 CHECK ("dirty" IN (0, 1)), "id" TEXT NOT NULL, "note_id" TEXT NOT NULL REFERENCES notes (id) ON DELETE CASCADE, "text" TEXT NOT NULL DEFAULT \'\', "checked" INTEGER NOT NULL DEFAULT 0 CHECK ("checked" IN (0, 1)), "indent" INTEGER NOT NULL DEFAULT 0, "sort_key" TEXT NOT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "labels" ("updated_at_ms" INTEGER NOT NULL, "deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("deleted" IN (0, 1)), "dirty" INTEGER NOT NULL DEFAULT 1 CHECK ("dirty" IN (0, 1)), "id" TEXT NOT NULL, "name" TEXT NOT NULL, "sort_key" TEXT NOT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "note_labels" ("note_id" TEXT NOT NULL REFERENCES notes (id) ON DELETE CASCADE, "label_id" TEXT NOT NULL REFERENCES labels (id) ON DELETE CASCADE, "updated_at_ms" INTEGER NOT NULL, "deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("deleted" IN (0, 1)), PRIMARY KEY ("note_id", "label_id"))',
  'CREATE TABLE "attachments" ("updated_at_ms" INTEGER NOT NULL, "deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("deleted" IN (0, 1)), "dirty" INTEGER NOT NULL DEFAULT 1 CHECK ("dirty" IN (0, 1)), "id" TEXT NOT NULL, "note_id" TEXT NOT NULL REFERENCES notes (id) ON DELETE CASCADE, "rel_path" TEXT NOT NULL, "thumb_path" TEXT NOT NULL, "width" INTEGER NOT NULL, "height" INTEGER NOT NULL, "bytes" INTEGER NOT NULL, "mime" TEXT NOT NULL DEFAULT \'image/jpeg\', "sort_key" TEXT NOT NULL, "created_at_ms" INTEGER NOT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "recent_searches" ("folded" TEXT NOT NULL, "query" TEXT NOT NULL, "used_at_ms" INTEGER NOT NULL, PRIMARY KEY ("folded"))',
  'CREATE INDEX idx_notes_shelf ON notes (archived, deleted, pinned)',
  'CREATE INDEX idx_notes_order ON notes (sort_key)',
  'CREATE INDEX idx_notes_reminder ON notes (reminder_at_ms)',
  'CREATE INDEX idx_items_note ON checklist_items (note_id, sort_key)',
  'CREATE UNIQUE INDEX idx_labels_name ON labels (name COLLATE NOCASE) WHERE deleted = 0',
  'CREATE INDEX idx_note_labels_label ON note_labels (label_id)',
  'CREATE INDEX idx_attachments_note ON attachments (note_id, sort_key)',
  '''
CREATE VIRTUAL TABLE notes_fts USING fts5(
  title, body, items, labels,
  tokenize = 'unicode61 remove_diacritics 2',
  prefix = '1 2 3'
)''',
  '''
CREATE TRIGGER notes_fts_note_insert AFTER INSERT ON notes BEGIN DELETE FROM notes_fts WHERE rowid IN (SELECT n.rowid FROM notes n WHERE n.id = NEW.id); INSERT INTO notes_fts (rowid, title, body, items, labels)
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
WHERE n.id = NEW.id; END''',
  '''
CREATE TRIGGER notes_fts_note_update AFTER UPDATE OF title, body ON notes BEGIN DELETE FROM notes_fts WHERE rowid IN (SELECT n.rowid FROM notes n WHERE n.id = NEW.id); INSERT INTO notes_fts (rowid, title, body, items, labels)
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
WHERE n.id = NEW.id; END''',
  'CREATE TRIGGER notes_fts_note_delete AFTER DELETE ON notes BEGIN DELETE FROM notes_fts WHERE rowid = OLD.rowid; END',
  '''
CREATE TRIGGER notes_fts_item_insert AFTER INSERT ON checklist_items BEGIN DELETE FROM notes_fts WHERE rowid IN (SELECT n.rowid FROM notes n WHERE n.id = NEW.note_id); INSERT INTO notes_fts (rowid, title, body, items, labels)
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
WHERE n.id = NEW.note_id; END''',
  '''
CREATE TRIGGER notes_fts_item_update AFTER UPDATE OF "text", deleted ON checklist_items BEGIN DELETE FROM notes_fts WHERE rowid IN (SELECT n.rowid FROM notes n WHERE n.id = NEW.note_id); INSERT INTO notes_fts (rowid, title, body, items, labels)
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
WHERE n.id = NEW.note_id; END''',
  '''
CREATE TRIGGER notes_fts_item_delete AFTER DELETE ON checklist_items BEGIN DELETE FROM notes_fts WHERE rowid IN (SELECT n.rowid FROM notes n WHERE n.id = OLD.note_id); INSERT INTO notes_fts (rowid, title, body, items, labels)
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
WHERE n.id = OLD.note_id; END''',
  '''
CREATE TRIGGER notes_fts_link_insert AFTER INSERT ON note_labels BEGIN DELETE FROM notes_fts WHERE rowid IN (SELECT n.rowid FROM notes n WHERE n.id = NEW.note_id); INSERT INTO notes_fts (rowid, title, body, items, labels)
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
WHERE n.id = NEW.note_id; END''',
  '''
CREATE TRIGGER notes_fts_link_update AFTER UPDATE OF deleted ON note_labels BEGIN DELETE FROM notes_fts WHERE rowid IN (SELECT n.rowid FROM notes n WHERE n.id = NEW.note_id); INSERT INTO notes_fts (rowid, title, body, items, labels)
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
WHERE n.id = NEW.note_id; END''',
  '''
CREATE TRIGGER notes_fts_link_delete AFTER DELETE ON note_labels BEGIN DELETE FROM notes_fts WHERE rowid IN (SELECT n.rowid FROM notes n WHERE n.id = OLD.note_id); INSERT INTO notes_fts (rowid, title, body, items, labels)
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
WHERE n.id = OLD.note_id; END''',
  '''
CREATE TRIGGER notes_fts_label_update AFTER UPDATE OF name, deleted ON labels BEGIN DELETE FROM notes_fts WHERE rowid IN (SELECT n.rowid FROM notes n WHERE n.id IN (SELECT note_id FROM note_labels WHERE label_id = NEW.id)); INSERT INTO notes_fts (rowid, title, body, items, labels)
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
WHERE n.id IN (SELECT note_id FROM note_labels WHERE label_id = NEW.id); END''',
];
