import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:notes/data/media/image_processor.dart';
import 'package:path/path.dart' as p;

/// Compresses images with Android's own decoder and JPEG encoder.
///
/// flutter_image_compress scales an image down by `min(width / minWidth,
/// height / minHeight)`, never up. Asking for a long edge therefore means
/// passing the short edge the result should have as both limits: the short
/// side then sets the scale, whichever way EXIF turns the photo upright.
class CompressImageProcessor implements ImageProcessor {
  const CompressImageProcessor();

  static const _quality = 85;

  @override
  Future<ProcessedImage> process(
    File source, {
    required File image,
    required File thumb,
  }) async {
    var input = source;
    File? upright;
    try {
      var size = await _sizeOf(source);
      if (size == null) {
        // A format Flutter cannot size, such as HEIC on some phones: let
        // Android decode it to a full-size JPEG first, then size that. It goes
        // to the cache, outside the media folder, where a sweep would take it
        // for a file nothing refers to.
        upright = File(
          p.join(
            Directory.systemTemp.path,
            '${p.basenameWithoutExtension(image.path)}.full.jpg',
          ),
        );
        await _write(source, upright, bound: 1 << 30);
        input = upright;
        size = await _sizeOf(upright);
        if (size == null) {
          throw FileSystemException('Not a readable image', source.path);
        }
      }

      await _write(input, image, bound: _bound(size, ImageProcessor.longEdge));
      await _write(input, thumb, bound: _bound(size, ImageProcessor.thumbEdge));

      final stored = await _sizeOf(image);
      if (stored == null) {
        throw FileSystemException('The stored image is unreadable', image.path);
      }
      return ProcessedImage(
        width: stored.$1,
        height: stored.$2,
        bytes: await image.length(),
      );
    } finally {
      if (upright != null && upright.existsSync()) await upright.delete();
    }
  }

  /// The limit to pass as both minWidth and minHeight so the long edge comes
  /// out no longer than [edge].
  static int _bound((int, int) size, int edge) {
    final long = math.max(size.$1, size.$2);
    final short = math.min(size.$1, size.$2);
    if (long <= edge) return short;
    return math.max(1, short * edge ~/ long);
  }

  static Future<void> _write(File from, File to, {required int bound}) async {
    final written = await FlutterImageCompress.compressAndGetFile(
      from.path,
      to.path,
      minWidth: bound,
      minHeight: bound,
      quality: _quality,
    );
    if (written == null) {
      throw FileSystemException('The image could not be compressed', from.path);
    }
  }

  /// The pixel size in [file]'s header, or null when Flutter cannot read it.
  static Future<(int, int)?> _sizeOf(File file) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromFilePath(file.path);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      return (descriptor.width, descriptor.height);
    } on Object {
      return null;
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}
