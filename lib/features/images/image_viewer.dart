import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:notes/core/theme/app_colors.dart';
import 'package:notes/core/theme/tokens.dart';
import 'package:notes/core/theme/typography.dart';
import 'package:notes/core/ui/undo.dart';
import 'package:notes/data/media/media_store.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/domain/model/attachment.dart';
import 'package:notes/features/notes/notes_providers.dart';

/// Opens the images of [noteId] full screen, at [index].
Future<void> openImageViewer(
  BuildContext context, {
  required String noteId,
  required int index,
  bool readOnly = false,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) =>
        ImageViewer(noteId: noteId, initialIndex: index, readOnly: readOnly),
  ),
);

/// A note's images, one at a time and full screen: swipe between them, pinch
/// or double-tap to zoom, delete with undo.
class ImageViewer extends ConsumerStatefulWidget {
  const ImageViewer({
    required this.noteId,
    required this.initialIndex,
    this.readOnly = false,
    super.key,
  });

  final String noteId;
  final int initialIndex;

  /// A note in the trash: its images can be looked at, not deleted.
  final bool readOnly;

  @override
  ConsumerState<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends ConsumerState<ImageViewer> {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;
  bool _closing = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _delete(Attachment image) async {
    final attachments = ref.read(attachmentRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    await attachments.remove(image.id);
    showUndo(
      messenger,
      message: 'Image deleted',
      onUndo: () => attachments.restore(image.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    final note = ref.watch(noteByIdProvider(widget.noteId)).value;
    final images = note?.attachments ?? const <Attachment>[];
    final root = ref.watch(mediaRootProvider).value;

    // The last image was deleted: nothing is left to show.
    if (note != null && images.isEmpty && !_closing) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
    // After a delete or an undo the pages move under the counter, so it reads
    // the page actually showing.
    final showing = _pages.hasClients && _pages.position.haveDimensions
        ? _pages.page!.round()
        : _index;
    final index = images.isEmpty ? 0 : showing.clamp(0, images.length - 1);

    // The viewer is dark in both themes, so the status and navigation bar
    // icons turn light here, whatever the app's own theme asks for.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: colors.viewer,
        body: Stack(
          children: [
            if (root != null)
              PageView.builder(
                controller: _pages,
                itemCount: images.length,
                onPageChanged: (page) => setState(() => _index = page),
                itemBuilder: (context, page) => _ZoomableImage(
                  key: ValueKey(images[page].id),
                  file: MediaStore.resolve(root, images[page].relPath),
                  label: 'Image ${page + 1} of ${images.length}',
                ),
              ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Icon(Icons.arrow_back, color: colors.onViewer),
                    ),
                    Expanded(
                      child: Text(
                        images.isEmpty ? '' : '${index + 1} / ${images.length}',
                        textAlign: TextAlign.center,
                        style: AppText.meta.copyWith(color: colors.onViewer),
                      ),
                    ),
                    if (!widget.readOnly && images.isNotEmpty)
                      IconButton(
                        tooltip: 'Delete image',
                        onPressed: () => unawaited(_delete(images[index])),
                        icon: Icon(
                          Icons.delete_outline,
                          color: colors.onViewer,
                        ),
                      )
                    else
                      const SizedBox(width: 48),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One image that can be pinched or double-tapped into.
///
/// Panning is only on while zoomed in. At its normal size a sideways drag
/// belongs to the pages, so swiping to the next image keeps working.
class _ZoomableImage extends StatefulWidget {
  const _ZoomableImage({required this.file, required this.label, super.key});

  final File file;
  final String label;

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> {
  static const _doubleTapScale = 2.5;

  final _transform = TransformationController();
  Offset _doubleTapAt = Offset.zero;
  bool _zoomed = false;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _settle() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  void _toggleZoom() {
    if (_zoomed) {
      _transform.value = Matrix4.identity();
    } else {
      final at = _doubleTapAt;
      _transform.value = Matrix4.identity()
        ..translateByDouble(
          -at.dx * (_doubleTapScale - 1),
          -at.dy * (_doubleTapScale - 1),
          0,
          1,
        )
        ..scaleByDouble(_doubleTapScale, _doubleTapScale, 1, 1);
    }
    _settle();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: widget.label,
      child: GestureDetector(
        onDoubleTapDown: (details) => _doubleTapAt = details.localPosition,
        onDoubleTap: _toggleZoom,
        child: InteractiveViewer(
          transformationController: _transform,
          panEnabled: _zoomed,
          maxScale: 5,
          onInteractionEnd: (_) => _settle(),
          child: SizedBox.expand(
            child: Image.file(
              widget.file,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}
