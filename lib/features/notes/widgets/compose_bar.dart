import 'package:flutter/material.dart';
import 'package:notes/core/theme/app_colors.dart';
import 'package:notes/core/theme/tokens.dart';
import 'package:notes/core/theme/typography.dart';

/// The one control that is always in reach.
///
/// Capture is the job of this app, so the bar sits over the grid at thumb
/// height rather than hiding behind a menu. Most of it starts a note; the
/// buttons at its end start a list, a note from photos, or a note from the
/// camera.
class ComposeBar extends StatelessWidget {
  const ComposeBar({
    required this.onTap,
    required this.onNewList,
    required this.onAddImage,
    required this.onTakePhoto,
    super.key,
  });

  final VoidCallback onTap;
  final VoidCallback onNewList;
  final VoidCallback onAddImage;
  final VoidCallback onTakePhoto;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;

    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(Radii.bar),
      child: Container(
        // A minimum, not a fixed height: large text grows the bar rather
        // than clipping the label.
        constraints: const BoxConstraints(minHeight: Layout.composeBarHeight),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.bar),
          border: Border.all(color: colors.hairline),
        ),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label: 'Take a note',
                excludeSemantics: true,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(Radii.bar),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: Layout.composeBarHeight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Gap.lg,
                        vertical: Gap.sm,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.edit_outlined,
                            size: 18,
                            color: colors.inkMuted,
                          ),
                          const SizedBox(width: Gap.md),
                          Flexible(
                            child: Text(
                              'Take a note',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.uiLarge.copyWith(
                                color: colors.inkMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'New list',
              onPressed: onNewList,
              icon: Icon(Icons.check_box_outlined, color: colors.inkMuted),
            ),
            IconButton(
              tooltip: 'Add photos',
              onPressed: onAddImage,
              icon: Icon(Icons.image_outlined, color: colors.inkMuted),
            ),
            IconButton(
              tooltip: 'Take a photo',
              onPressed: onTakePhoto,
              icon: Icon(
                Icons.photo_camera_outlined,
                color: colors.inkMuted,
              ),
            ),
            const SizedBox(width: Gap.xs),
          ],
        ),
      ),
    );
  }
}
