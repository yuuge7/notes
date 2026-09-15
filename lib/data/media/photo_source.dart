import 'dart:io';

import 'package:image_picker/image_picker.dart';

/// Where new photos come from.
abstract interface class PhotoSource {
  /// Photos chosen in the phone's photo picker; empty when it was closed.
  Future<List<File>> pickPhotos();

  /// A photo taken with the camera, or null when none was taken.
  Future<File?> takePhoto();

  /// Photos chosen just before Android closed the app to free memory, which
  /// never reached the screen that asked for them.
  Future<List<File>> recoverLost();
}

/// Photos from the Android photo picker and the camera app.
///
/// Neither needs a storage or camera permission: the picker hands over only
/// what was chosen, and the camera app takes the photo itself.
class DevicePhotoSource implements PhotoSource {
  DevicePhotoSource([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  /// Photos taken from the picker at once.
  static const _limit = 20;

  final ImagePicker _picker;

  @override
  Future<List<File>> pickPhotos() async => [
    for (final photo in await _picker.pickMultiImage(
      limit: _limit,
      requestFullMetadata: false,
    ))
      File(photo.path),
  ];

  @override
  Future<File?> takePhoto() async {
    final photo = await _picker.pickImage(
      source: ImageSource.camera,
      requestFullMetadata: false,
    );
    return photo == null ? null : File(photo.path);
  }

  @override
  Future<List<File>> recoverLost() async {
    final response = await _picker.retrieveLostData();
    if (response.isEmpty) return const [];
    return [
      for (final photo in response.files ?? const <XFile>[]) File(photo.path),
    ];
  }
}
