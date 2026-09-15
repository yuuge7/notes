import 'package:freezed_annotation/freezed_annotation.dart';

part 'checklist_item.freezed.dart';
part 'checklist_item.g.dart';

@freezed
abstract class ChecklistItem with _$ChecklistItem {
  const factory ChecklistItem({
    required String id,
    required String noteId,
    required String text,
    required String sortKey,
    required DateTime updatedAt,
    @Default(false) bool checked,

    /// 0 or 1. One level of nesting only; children travel with their parent.
    @Default(0) int indent,
  }) = _ChecklistItem;

  factory ChecklistItem.fromJson(Map<String, dynamic> json) =>
      _$ChecklistItemFromJson(json);
}
