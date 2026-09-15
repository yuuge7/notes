import 'package:freezed_annotation/freezed_annotation.dart';

part 'attachment.freezed.dart';
part 'attachment.g.dart';

@freezed
abstract class Attachment with _$Attachment {
  const factory Attachment({
    required String id,
    required String noteId,

    /// Path relative to the app documents directory, never absolute: the
    /// documents path changes between installs and restores.
    required String relPath,
    required String thumbPath,
    required int width,
    required int height,
    required int bytes,
    required String mime,
    required String sortKey,
    required DateTime createdAt,
  }) = _Attachment;

  factory Attachment.fromJson(Map<String, dynamic> json) =>
      _$AttachmentFromJson(json);

  const Attachment._();
}
