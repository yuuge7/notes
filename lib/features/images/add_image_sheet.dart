import 'package:flutter/material.dart';
import 'package:notes/core/theme/app_colors.dart';
import 'package:notes/core/theme/tokens.dart';
import 'package:notes/core/theme/typography.dart';

/// Where a new image comes from.
enum PhotoChoice { pick, camera }

/// Asks where an image should come from. Null when the sheet is dismissed.
Future<PhotoChoice?> showAddImageSheet(BuildContext context) =>
    showModalBottomSheet<PhotoChoice>(
      context: context,
      builder: (_) => const AddImageSheet(),
    );

class AddImageSheet extends StatelessWidget {
  const AddImageSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: Gap.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.sm),
              child: Semantics(
                header: true,
                child: Text(
                  'ADD IMAGE',
                  style: AppText.metaStrong.copyWith(color: colors.inkMuted),
                ),
              ),
            ),
            const _ChoiceRow(
              choice: PhotoChoice.pick,
              icon: Icons.photo_library_outlined,
              label: 'Choose photos',
            ),
            const _ChoiceRow(
              choice: PhotoChoice.camera,
              icon: Icons.photo_camera_outlined,
              label: 'Take a photo',
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.choice,
    required this.icon,
    required this.label,
  });

  final PhotoChoice choice;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;

    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(choice),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.xl,
              vertical: Gap.sm,
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: colors.inkMuted),
                const SizedBox(width: Gap.lg),
                Expanded(
                  child: Text(
                    label,
                    style: AppText.uiLarge.copyWith(color: colors.ink),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
