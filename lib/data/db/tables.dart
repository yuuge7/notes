import 'package:drift/drift.dart';
import 'package:notes/domain/model/note_type.dart';
import 'package:notes/domain/model/pigment.dart';
import 'package:notes/domain/model/reminder_rule.dart';

/// Columns every table carries so a sync backend can be added without a
/// migration: a monotonic [updatedAtMs], a [deleted] tombstone instead of a
/// hard delete, and a [dirty] flag marking rows the device has not pushed.
mixin SyncColumns on Table {
  IntColumn get updatedAtMs => integer()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();
}

@DataClassName('NoteRow')
@TableIndex(name: 'idx_notes_shelf', columns: {#archived, #deleted, #pinned})
@TableIndex(name: 'idx_notes_order', columns: {#sortKey})
@TableIndex(name: 'idx_notes_reminder', columns: {#reminderAtMs})
class Notes extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get type =>
      textEnum<NoteType>().withDefault(const Constant('text'))();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get body => text().withDefault(const Constant(''))();
  TextColumn get pigment =>
      textEnum<Pigment>().withDefault(const Constant('graphite'))();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  /// Fractional index. Manual order wins over date order once a note is
  /// dragged; see SortKey.
  TextColumn get sortKey => text()();

  IntColumn get reminderAtMs => integer().nullable()();
  TextColumn get reminderRule => textEnum<ReminderRule>().nullable()();
  BoolColumn get reminderDone => boolean().withDefault(const Constant(false))();

  IntColumn get createdAtMs => integer()();

  /// When the note went to the trash. The purge job reads this, not
  /// [updatedAtMs], so editing a trashed note does not extend its stay.
  IntColumn get deletedAtMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ChecklistItemRow')
@TableIndex(name: 'idx_items_note', columns: {#noteId, #sortKey})
class ChecklistItems extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get noteId =>
      text().references(Notes, #id, onDelete: KeyAction.cascade)();
  // Named `content` in Dart because a getter called `text` would shadow
  // drift's own `text()` column builder.
  TextColumn get content => text().named('text').withDefault(const Constant(''))();
  BoolColumn get checked => boolean().withDefault(const Constant(false))();
  IntColumn get indent => integer().withDefault(const Constant(0))();
  TextColumn get sortKey => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('LabelRow')
// One live label per name, ignoring case: "home" and "Home" are the same
// label. A deleted label keeps its row as a tombstone for sync, so its name
// has to be free to use again.
@TableIndex.sql(
  'CREATE UNIQUE INDEX idx_labels_name ON labels (name COLLATE NOCASE) '
  'WHERE deleted = 0',
)
class Labels extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get sortKey => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('NoteLabelRow')
@TableIndex(name: 'idx_note_labels_label', columns: {#labelId})
class NoteLabels extends Table {
  TextColumn get noteId =>
      text().references(Notes, #id, onDelete: KeyAction.cascade)();
  TextColumn get labelId =>
      text().references(Labels, #id, onDelete: KeyAction.cascade)();
  IntColumn get updatedAtMs => integer()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {noteId, labelId};
}

/// The last few searches, offered again when the search field is empty.
/// Kept on this device only: no sync columns.
@DataClassName('RecentSearchRow')
class RecentSearches extends Table {
  /// The query folded to lower case, so "Bike" and "bike" are one entry.
  TextColumn get folded => text()();

  /// The query as it was last typed.
  TextColumn get query => text()();
  IntColumn get usedAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {folded};
}

/// Settings chosen on this device, one row per setting, each value stored as
/// text. Kept on this device only: no sync columns, and not part of an export.
@DataClassName('PreferenceRow')
class Preferences extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DataClassName('AttachmentRow')
@TableIndex(name: 'idx_attachments_note', columns: {#noteId, #sortKey})
class Attachments extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get noteId =>
      text().references(Notes, #id, onDelete: KeyAction.cascade)();

  /// Relative to the app documents directory. Absolute paths do not survive
  /// a reinstall or a restore.
  TextColumn get relPath => text()();
  TextColumn get thumbPath => text()();
  IntColumn get width => integer()();
  IntColumn get height => integer()();
  IntColumn get bytes => integer()();
  TextColumn get mime => text().withDefault(const Constant('image/jpeg'))();
  TextColumn get sortKey => text()();
  IntColumn get createdAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
