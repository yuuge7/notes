import 'dart:io';

import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// The system's own ways to move a file in or out of the app: the pickers to
/// save and open a file, and the share sheet. None needs a storage permission;
/// the person picks the place, and Android grants access to that alone.
abstract interface class DocumentPicker {
  /// Asks where to save [file], suggesting [name], and copies it there.
  /// Returns false when the picker was closed without saving.
  Future<bool> save(
    File file, {
    required String name,
    required String mimeType,
  });

  /// Asks for a file and returns a copy the app can read, or null when the
  /// picker was closed without choosing.
  Future<File?> open({required List<String> mimeTypes});

  /// Offers [file] to other apps through the share sheet.
  Future<void> share(
    File file, {
    required String name,
    required String mimeType,
  });
}

/// Android's document pickers, reached through MainActivity, and share_plus.
class DeviceDocumentPicker implements DocumentPicker {
  static const _channel = MethodChannel('com.ionel.notes/documents');

  @override
  Future<bool> save(
    File file, {
    required String name,
    required String mimeType,
  }) async =>
      await _channel.invokeMethod<bool>('save', {
        'path': file.path,
        'name': name,
        'mimeType': mimeType,
      }) ??
      false;

  @override
  Future<File?> open({required List<String> mimeTypes}) async {
    final path = await _channel.invokeMethod<String>('open', {
      'mimeTypes': mimeTypes,
    });
    return path == null ? null : File(path);
  }

  @override
  Future<void> share(
    File file, {
    required String name,
    required String mimeType,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType, name: name)],
        fileNameOverrides: [name],
      ),
    );
  }
}
