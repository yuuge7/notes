import 'dart:io';

import 'package:notes/data/backup/document_picker.dart';

/// Stands in for Android's save and open pickers and the share sheet.
class FakeDocumentPicker implements DocumentPicker {
  /// What the open picker hands back next; null as if it were closed.
  File? toOpen;

  /// Whether the save picker saves, or is closed without saving.
  bool saves = true;

  /// The names files were saved under, in order.
  final saved = <String>[];

  /// The names files were shared under, in order.
  final shared = <String>[];

  int openCalls = 0;

  @override
  Future<File?> open({required List<String> mimeTypes}) async {
    openCalls++;
    return toOpen;
  }

  @override
  Future<bool> save(
    File file, {
    required String name,
    required String mimeType,
  }) async {
    if (!file.existsSync()) throw StateError('Nothing to save at ${file.path}');
    if (saves) saved.add(name);
    return saves;
  }

  @override
  Future<void> share(
    File file, {
    required String name,
    required String mimeType,
  }) async => shared.add(name);
}
