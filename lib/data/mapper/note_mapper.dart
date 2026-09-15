import 'package:notes/data/db/database.dart';
import 'package:notes/domain/model/attachment.dart';
import 'package:notes/domain/model/checklist_item.dart';
import 'package:notes/domain/model/label.dart';
import 'package:notes/domain/model/note.dart';

DateTime _at(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);

DateTime? _atOrNull(int? ms) =>
    ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);

extension NoteRowMapper on NoteRow {
  Note toDomain({
    List<ChecklistItem> items = const [],
    List<Label> labels = const [],
    List<Attachment> attachments = const [],
  }) {
    return Note(
      id: id,
      type: type,
      title: title,
      body: body,
      pigment: pigment,
      sortKey: sortKey,
      createdAt: _at(createdAtMs),
      updatedAt: _at(updatedAtMs),
      pinned: pinned,
      archived: archived,
      deleted: deleted,
      deletedAt: _atOrNull(deletedAtMs),
      reminderAt: _atOrNull(reminderAtMs),
      reminderRule: reminderRule,
      reminderDone: reminderDone,
      items: items,
      labels: labels,
      attachments: attachments,
    );
  }
}

extension ChecklistItemRowMapper on ChecklistItemRow {
  ChecklistItem toDomain() => ChecklistItem(
    id: id,
    noteId: noteId,
    text: content,
    sortKey: sortKey,
    updatedAt: _at(updatedAtMs),
    checked: checked,
    indent: indent,
  );
}

extension LabelRowMapper on LabelRow {
  Label toDomain() => Label(
    id: id,
    name: name,
    sortKey: sortKey,
    updatedAt: _at(updatedAtMs),
  );
}

extension AttachmentRowMapper on AttachmentRow {
  Attachment toDomain() => Attachment(
    id: id,
    noteId: noteId,
    relPath: relPath,
    thumbPath: thumbPath,
    width: width,
    height: height,
    bytes: bytes,
    mime: mime,
    sortKey: sortKey,
    createdAt: _at(createdAtMs),
  );
}
