import 'dart:io';

import 'package:path/path.dart' as p;

/// Where images live on disk: each image and its thumbnail as JPEG files
/// under `media/` in the app's documents directory.
///
/// The database stores paths relative to that directory, always with forward
/// slashes. Absolute paths do not survive a reinstall or a restore; relative
/// ones do.
class MediaStore {
  MediaStore(this._root);

  static const folder = 'media';

  /// The app's documents directory, resolved once.
  final Future<Directory> _root;

  /// Where the image for [attachmentId] is stored, relative to the root.
  static String imagePathFor(String attachmentId) => '$folder/$attachmentId.jpg';

  /// Where the thumbnail for [attachmentId] is stored, relative to the root.
  static String thumbPathFor(String attachmentId) =>
      '$folder/thumbs/$attachmentId.jpg';

  /// [relPath] as a file under [root].
  static File resolve(Directory root, String relPath) =>
      File(p.joinAll([root.path, ...relPath.split('/')]));

  Future<File> file(String relPath) async => resolve(await _root, relPath);

  /// The file for [relPath], with its folder created, ready to be written.
  Future<File> prepare(String relPath) async {
    final file = await this.file(relPath);
    await file.parent.create(recursive: true);
    return file;
  }

  /// Deletes the files at [relPaths], passing over any already gone.
  Future<void> delete(Iterable<String> relPaths) async {
    for (final relPath in relPaths) {
      try {
        await (await file(relPath)).delete();
      } on FileSystemException {
        // Already gone, which is the point.
      }
    }
  }

  /// Every file under the media folder, relative to the root.
  Future<List<String>> listAll() async {
    final root = await _root;
    final dir = Directory(p.join(root.path, folder));
    if (!dir.existsSync()) return const [];
    final paths = <String>[];
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        paths.add(p.split(p.relative(entity.path, from: root.path)).join('/'));
      }
    }
    return paths;
  }
}
