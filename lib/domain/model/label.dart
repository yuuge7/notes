import 'package:freezed_annotation/freezed_annotation.dart';

part 'label.freezed.dart';
part 'label.g.dart';

@freezed
abstract class Label with _$Label {
  const factory Label({
    required String id,
    required String name,
    required String sortKey,
    required DateTime updatedAt,
  }) = _Label;

  factory Label.fromJson(Map<String, dynamic> json) => _$LabelFromJson(json);
}
