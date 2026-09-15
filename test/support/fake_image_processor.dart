import 'dart:async';
import 'dart:io';

import 'package:notes/data/media/image_processor.dart';

/// Stands in for image compression: the "image" is the source's bytes, the
/// thumbnail a few of them.
class FakeImageProcessor implements ImageProcessor {
  /// A source whose path contains this fails, as an unreadable photo would.
  String failing = 'broken';

  /// When set, each image waits for it after its files are written, as a slow
  /// compression would.
  Completer<void>? gate;

  /// Images processed so far.
  int processed = 0;

  @override
  Future<ProcessedImage> process(
    File source, {
    required File image,
    required File thumb,
  }) async {
    if (source.path.contains(failing)) {
      throw FileSystemException('Not an image', source.path);
    }
    final bytes = await source.readAsBytes();
    await image.writeAsBytes(bytes);
    await thumb.writeAsBytes(bytes.take(8).toList());
    await gate?.future;
    processed++;
    return ProcessedImage(width: 2048, height: 1536, bytes: bytes.length);
  }
}
