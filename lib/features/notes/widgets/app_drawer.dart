import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:notes/core/theme/app_colors.dart';
import 'package:notes/core/theme/tokens.dart';
import 'package:notes/core/theme/typography.dart';
import 'package:notes/domain/model/label.dart';
import 'package:notes/features/labels/label_providers.dart';

/// Moves between shelves, reminders, and labels. Settings joins the list in
/// its own milestone.
class AppDrawer extends ConsumerWidget {
  const AppDrawer({required this.currentPath, super.key});

  /// The route of the screen that opened the drawer, marked as current.
  final String currentPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colors;
    final labels = ref.watch(labelsProvider).value ?? const <Label>[];

    void go(String path) {
      Navigator.of(context).pop();
      if (path != currentPath) context.go(path);
    }

    void editLabels() {
      // Read the router before the drawer closes and its context goes.
      final router = GoRouter.of(context);
      Navigator.of(context).pop();
      unawaited(router.push('/labels'));
    }

    return Drawer(
      backgroundColor: colors.ground,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(
          right: Radius.circular(Radii.sheet),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: Gap.lg),
          children: [
            Padding(
              padding: const EdgeInsets.all(Gap.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Notes',
                    style: AppText.display.copyWith(
                      color: colors.ink,
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(height: Gap.xs),
                  // True and worth knowing: nothing here leaves the phone.
                  Text(
                    'KEPT ON THIS DEVICE',
                    style: AppText.meta.copyWith(color: colors.inkMuted),
                  ),
                ],
              ),
            ),
            _DrawerItem(
              label: 'Notes',
              icon: Icons.edit_note_outlined,
              selected: currentPath == '/',
              onTap: () => go('/'),
            ),
            _DrawerItem(
              label: 'Reminders',
              icon: Icons.alarm_outlined,
              selected: currentPath == '/reminders',
              onTap: () => go('/reminders'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Gap.xl,
                Gap.lg,
                Gap.sm,
                Gap.xs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        'LABELS',
                        style: AppText.metaStrong.copyWith(
                          color: colors.inkMuted,
                        ),
                      ),
                    ),
                  ),
                  if (labels.isNotEmpty)
                    TextButton(
                      onPressed: editLabels,
                      child: const Text('Edit labels'),
                    ),
                ],
              ),
            ),
            for (final label in labels)
              _DrawerItem(
                label: label.name,
                icon: Icons.label_outline,
                selected: currentPath == '/label/${label.id}',
                onTap: () => go('/label/${label.id}'),
              ),
            if (labels.isEmpty)
              _DrawerItem(
                label: 'Create a label',
                icon: Icons.add,
                selected: false,
                onTap: editLabels,
              ),
            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: Gap.xl,
                vertical: Gap.md,
              ),
              child: Divider(),
            ),
            _DrawerItem(
              label: 'Archive',
              icon: Icons.archive_outlined,
              selected: currentPath == '/archive',
              onTap: () => go('/archive'),
            ),
            _DrawerItem(
              label: 'Trash',
              icon: Icons.delete_outline,
              selected: currentPath == '/trash',
              onTap: () => go('/trash'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 2),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? colors.accentWash : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.chip),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(Radii.chip),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      size: 22,
                      color: selected ? colors.accent : colors.inkMuted,
                    ),
                    const SizedBox(width: Gap.lg),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: (selected ? AppText.uiStrong : AppText.ui)
                            .copyWith(color: colors.ink),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
