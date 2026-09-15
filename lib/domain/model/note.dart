import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:notes/core/util/reminder_time.dart';
import 'package:notes/domain/model/attachment.dart';
import 'package:notes/domain/model/checklist_item.dart';
import 'package:notes/domain/model/label.dart';
import 'package:notes/domain/model/note_type.dart';
import 'package:notes/domain/model/pigment.dart';
import 'package:notes/domain/model/reminder_rule.dart';

part 'note.freezed.dart';
part 'note.g.dart';

@freezed
abstract class Note with _$Note {
  const factory Note({
    required String id,
    required NoteType type,
    required String title,
    required String body,
    required Pigment pigment,
    required String sortKey,
    required DateTime createdAt,
    required DateTime updatedAt,
    @Default(false) bool pinned,
    @Default(false) bool archived,
    @Default(false) bool deleted,
    DateTime? deletedAt,
    DateTime? reminderAt,
    ReminderRule? reminderRule,
    @Default(false) bool reminderDone,
    @Default(<ChecklistItem>[]) List<ChecklistItem> items,
    @Default(<Label>[]) List<Label> labels,
    @Default(<Attachment>[]) List<Attachment> attachments,
  }) = _Note;

  factory Note.fromJson(Map<String, dynamic> json) => _$NoteFromJson(json);

  const Note._();

  bool get isChecklist => type == NoteType.checklist;

  /// True when there is nothing worth keeping. An empty note is discarded when
  /// the editor closes rather than saved as a blank card.
  bool get isBlank =>
      title.trim().isEmpty &&
      body.trim().isEmpty &&
      attachments.isEmpty &&
      items.every((item) => item.text.trim().isEmpty);

  bool get hasReminder => reminderAt != null;

  /// A one-off reminder that has rung and not been marked done. A repeating
  /// reminder is never overdue: it always has a next time.
  bool get isReminderOverdue =>
      reminderAt != null &&
      reminderRule == null &&
      !reminderDone &&
      reminderAt!.isBefore(DateTime.now());

  /// When the reminder rings next: for a repeating reminder the coming ring,
  /// not the first one.
  DateTime? get nextReminderAt => reminderAt == null
      ? null
      : ReminderTime.next(reminderAt!, reminderRule, DateTime.now());

  List<ChecklistItem> get uncheckedItems =>
      items.where((item) => !item.checked).toList();

  List<ChecklistItem> get checkedItems =>
      items.where((item) => item.checked).toList();
}
