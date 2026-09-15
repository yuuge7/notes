import 'dart:io';

import 'package:notes/data/media/photo_source.dart';

/// Hands back whatever photos a test has lined up, standing in for the photo
/// picker and the camera.
class FakePhotoSource implements PhotoSource {
  /// What the picker returns next.
  List<File> picks = const [];

  /// What the camera returns next.
  File? photo;

  /// What recovering a lost pick returns, once.
  List<File> lost = const [];

  int pickCalls = 0;
  int cameraCalls = 0;

  @override
  Future<List<File>> pickPhotos() async {
    pickCalls++;
    return picks;
  }

  @override
  Future<File?> takePhoto() async {
    cameraCalls++;
    return photo;
  }

  @override
  Future<List<File>> recoverLost() async {
    final recovered = lost;
    lost = const [];
    return recovered;
  }
}
