/// The database as schema version 1 created it, taken from `sqlite_master`
/// of a fresh version 1 database. Migration tests build this by hand and let
/// the current app upgrade it, as an install from before labels and search
/// would be upgraded on a phone.
const schemaV1 = [
  'CREATE TABLE "notes" ("updated_at_ms" INTEGER NOT NULL, "deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("deleted" IN (0, 1)), "dirty" INTEGER NOT NULL DEFAULT 1 CHECK ("dirty" IN (0, 1)), "id" TEXT NOT NULL, "type" TEXT NOT NULL DEFAULT \'text\', "title" TEXT NOT NULL DEFAULT \'\', "body" TEXT NOT NULL DEFAULT \'\', "pigment" TEXT NOT NULL DEFAULT \'graphite\', "pinned" INTEGER NOT NULL DEFAULT 0 CHECK ("pinned" IN (0, 1)), "archived" INTEGER NOT NULL DEFAULT 0 CHECK ("archived" IN (0, 1)), "sort_key" TEXT NOT NULL, "reminder_at_ms" INTEGER NULL, "reminder_rule" TEXT NULL, "reminder_done" INTEGER NOT NULL DEFAULT 0 CHECK ("reminder_done" IN (0, 1)), "created_at_ms" INTEGER NOT NULL, "deleted_at_ms" INTEGER NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "checklist_items" ("updated_at_ms" INTEGER NOT NULL, "deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("deleted" IN (0, 1)), "dirty" INTEGER NOT NULL DEFAULT 1 CHECK ("dirty" IN (0, 1)), "id" TEXT NOT NULL, "note_id" TEXT NOT NULL REFERENCES notes (id) ON DELETE CASCADE, "text" TEXT NOT NULL DEFAULT \'\', "checked" INTEGER NOT NULL DEFAULT 0 CHECK ("checked" IN (0, 1)), "indent" INTEGER NOT NULL DEFAULT 0, "sort_key" TEXT NOT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "labels" ("updated_at_ms" INTEGER NOT NULL, "deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("deleted" IN (0, 1)), "dirty" INTEGER NOT NULL DEFAULT 1 CHECK ("dirty" IN (0, 1)), "id" TEXT NOT NULL, "name" TEXT NOT NULL UNIQUE, "sort_key" TEXT NOT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "note_labels" ("note_id" TEXT NOT NULL REFERENCES notes (id) ON DELETE CASCADE, "label_id" TEXT NOT NULL REFERENCES labels (id) ON DELETE CASCADE, "updated_at_ms" INTEGER NOT NULL, "deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("deleted" IN (0, 1)), PRIMARY KEY ("note_id", "label_id"))',
  'CREATE TABLE "attachments" ("updated_at_ms" INTEGER NOT NULL, "deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("deleted" IN (0, 1)), "dirty" INTEGER NOT NULL DEFAULT 1 CHECK ("dirty" IN (0, 1)), "id" TEXT NOT NULL, "note_id" TEXT NOT NULL REFERENCES notes (id) ON DELETE CASCADE, "rel_path" TEXT NOT NULL, "thumb_path" TEXT NOT NULL, "width" INTEGER NOT NULL, "height" INTEGER NOT NULL, "bytes" INTEGER NOT NULL, "mime" TEXT NOT NULL DEFAULT \'image/jpeg\', "sort_key" TEXT NOT NULL, "created_at_ms" INTEGER NOT NULL, PRIMARY KEY ("id"))',
  'CREATE INDEX idx_notes_shelf ON notes (archived, deleted, pinned)',
  'CREATE INDEX idx_notes_order ON notes (sort_key)',
  'CREATE INDEX idx_notes_reminder ON notes (reminder_at_ms)',
  'CREATE INDEX idx_items_note ON checklist_items (note_id, sort_key)',
  'CREATE INDEX idx_note_labels_label ON note_labels (label_id)',
  'CREATE INDEX idx_attachments_note ON attachments (note_id, sort_key)',
];
