import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:notes/core/theme/app_colors.dart';
import 'package:notes/core/theme/typography.dart';
import 'package:notes/data/media/media_store.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/domain/model/attachment.dart';

/// A note's images across the top of its card.
///
/// One image keeps its own shape, within limits. Two sit side by side. Three
/// or more show as one large and two small, the last small one counting the
/// images that did not fit. Thumbnails only: the full images are never decoded
/// for a card.
class ImageMosaic extends ConsumerWidget {
  const ImageMosaic({required this.images, super.key});

  /// Not empty.
  final List<Attachment> images;

  /// The gap between tiles.
  static const _gap = 2.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final root = ref.watch(mediaRootProvider).value;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final shown = images.take(3).toList();

        Widget tile(Attachment image, double w, double h, {int more = 0}) =>
            _Thumb(root: root, image: image, width: w, height: h, more: more);

        switch (shown.length) {
          case 1:
            final image = shown.single;
            final aspect = (image.width / image.height).clamp(0.8, 1.9);
            return tile(image, width, width / aspect);
          case 2:
            final side = (width - _gap) / 2;
            return Row(
              children: [
                tile(shown[0], side, side),
                const SizedBox(width: _gap),
                tile(shown[1], side, side),
              ],
            );
          default:
            final large = (width - _gap) * 2 / 3;
            final small = width - _gap - large;
            final smallHeight = (large - _gap) / 2;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tile(shown[0], large, large),
                const SizedBox(width: _gap),
                Column(
                  children: [
                    tile(shown[1], small, smallHeight),
                    const SizedBox(height: _gap),
                    tile(
                      shown[2],
                      small,
                      smallHeight,
                      more: images.length - shown.length,
                    ),
                  ],
                ),
              ],
            );
        }
      },
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.root,
    required this.image,
    required this.width,
    required this.height,
    required this.more,
  });

  /// Null until the documents directory is known.
  final Directory? root;
  final Attachment image;
  final double width;
  final double height;

  /// Images beyond this tile, counted on it.
  final int more;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    final root = this.root;

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Holds the tile's place, so the card does not grow when the
          // thumbnail arrives.
          ColoredBox(color: colors.hairline),
          if (root != null)
            Image.file(
              MediaStore.resolve(root, image.thumbPath),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          if (more > 0)
            ColoredBox(
              color: colors.viewer.withValues(alpha: 0.55),
              child: Center(
                child: Text(
                  '+$more',
                  style: AppText.metaStrong.copyWith(
                    color: colors.onViewer,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
