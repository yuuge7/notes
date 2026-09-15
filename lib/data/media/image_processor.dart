import 'dart:io';

import 'package:flutter/foundation.dart';

/// The size of an image as stored.
@immutable
class ProcessedImage {
  const ProcessedImage({
    required this.width,
    required this.height,
    required this.bytes,
  });

  final int width;
  final int height;

  /// The stored image's file size.
  final int bytes;
}

/// Turns a picked or photographed image into the app's own copy and a
/// thumbnail.
abstract interface class ImageProcessor {
  /// The longest edge a stored image keeps, in pixels.
  static const int longEdge = 2048;

  /// The longest edge of a thumbnail, in pixels.
  static const int thumbEdge = 400;

  /// Writes [source], turned upright, as a JPEG no larger than [longEdge] on
  /// its long edge to [image], and one no larger than [thumbEdge] to [thumb].
  /// Returns the size of [image] as written.
  ///
  /// Throws when [source] cannot be read as an image.
  Future<ProcessedImage> process(
    File source, {
    required File image,
    required File thumb,
  });
}
