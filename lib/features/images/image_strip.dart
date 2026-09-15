import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:notes/core/theme/app_colors.dart';
import 'package:notes/core/theme/tokens.dart';
import 'package:notes/core/theme/typography.dart';
import 'package:notes/data/media/media_store.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/domain/model/attachment.dart';

/// Every image on a note, at the top of its page.
///
/// Images fill rows of up to three. The tiles in a row share one height, set
/// so the row spans the page with each image near its own shape; a single
/// image stops at a height that leaves room for the writing below it.
class ImageStrip extends ConsumerWidget {
  const ImageStrip({
    required this.images,
    required this.onOpen,
    this.adding = 0,
    super.key,
  });

  final List<Attachment> images;

  /// Opens the image at the given position full screen.
  final ValueChanged<int> onOpen;

  /// Photos still being compressed, shown as a line under the strip.
  final int adding;

  static const _perRow = 3;
  static const double _gap = Gap.xs;
  static const _maxRowHeight = 360.0;

  /// The width to decode [image] at, so that cropped to fill its tile it is
  /// never drawn larger than it was decoded. A panorama wider than its tile
  /// is scaled to the tile's height, which needs more width than the tile.
  static int _decodeWidth(
    Attachment image, {
    required double tileWidth,
    required double tileHeight,
    required double dpr,
  }) {
    final imageAspect = image.width / math.max(1, image.height);
    final tileAspect = tileWidth / tileHeight;
    return (tileWidth * math.max(1, imageAspect / tileAspect) * dpr).ceil();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colors;
    final root = ref.watch(mediaRootProvider).value;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final children = <Widget>[];

        for (var start = 0; start < images.length; start += _perRow) {
          final row = images.sublist(
            start,
            math.min(start + _perRow, images.length),
          );
          final aspects = [
            for (final image in row)
              (image.width / math.max(1, image.height)).clamp(0.5, 2.5),
          ];
          final total = aspects.fold<double>(0, (sum, aspect) => sum + aspect);
          final free = width - _gap * (row.length - 1);
          final height = math.min(_maxRowHeight, free / total);

          if (children.isNotEmpty) children.add(const SizedBox(height: _gap));
          children.add(
            SizedBox(
              height: height,
              child: Row(
                children: [
                  for (final (i, image) in row.indexed) ...[
                    if (i > 0) const SizedBox(width: _gap),
                    Expanded(
                      flex: (aspects[i] * 1000).round(),
                      child: _Tile(
                        root: root,
                        image: image,
                        label: 'Image ${start + i + 1} of ${images.length}',
                        decodeWidth: _decodeWidth(
                          image,
                          tileWidth: free * aspects[i] / total,
                          tileHeight: height,
                          dpr: dpr,
                        ),
                        onTap: () => onOpen(start + i),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        if (adding > 0) {
          if (children.isNotEmpty) {
            children.add(const SizedBox(height: Gap.sm));
          }
          children.add(
            Semantics(
              liveRegion: true,
              child: Text(
                adding == 1 ? 'ADDING 1 PHOTO' : 'ADDING $adding PHOTOS',
                style: AppText.meta.copyWith(color: colors.inkMuted),
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.root,
    required this.image,
    required this.label,
    required this.decodeWidth,
    required this.onTap,
  });

  final Directory? root;
  final Attachment image;
  final String label;

  /// The width to decode the image at: the tile's own width in pixels, not
  /// the stored image's.
  final int decodeWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    final root = this.root;

    return Semantics(
      button: true,
      image: true,
      label: label,
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.small),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: colors.hairline),
            if (root != null)
              Image.file(
                MediaStore.resolve(root, image.relPath),
                fit: BoxFit.cover,
                cacheWidth: decodeWidth,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            Material(
              type: MaterialType.transparency,
              child: InkWell(onTap: onTap),
            ),
          ],
        ),
      ),
    );
  }
}
