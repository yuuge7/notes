import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:notes/core/theme/app_colors.dart';
import 'package:notes/core/theme/tokens.dart';
import 'package:notes/core/theme/typography.dart';
import 'package:notes/data/device/home_widgets.dart';
import 'package:notes/domain/model/label.dart';
import 'package:notes/features/labels/label_providers.dart';
import 'package:notes/features/settings/settings_rows.dart';

/// Asks what a notes widget placed from settings shows. Returns null when the
/// sheet is dismissed.
///
/// A widget placed from the launcher's own list asks the same on the home
/// screen, but a launcher placing one for the app skips that, so the choice
/// is made here first.
Future<WidgetFeed?> showWidgetFeedSheet(BuildContext context) =>
    showModalBottomSheet<WidgetFeed>(
      context: context,
      builder: (_) => const WidgetFeedSheet(),
    );

/// Every note, the pinned ones, or one label's, as the widget's own settings
/// offer them.
class WidgetFeedSheet extends ConsumerWidget {
  const WidgetFeedSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labels = ref.watch(labelsProvider).value ?? const <Label>[];
    void choose(WidgetFeed feed) => Navigator.of(context).pop(feed);

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: Gap.lg),
        children: [
          const SettingsHeader('SHOW ON THIS WIDGET', top: 0),
          SettingsAction(
            icon: Icons.view_agenda_outlined,
            label: AllFeed.name,
            detail: 'Pinned first, then the latest',
            onTap: () => choose(const AllFeed()),
          ),
          SettingsAction(
            icon: Icons.push_pin_outlined,
            label: PinnedFeed.name,
            detail: 'Only the notes pinned to the top',
            onTap: () => choose(const PinnedFeed()),
          ),
          const SettingsHeader('LABELS'),
          for (final label in labels)
            SettingsAction(
              icon: Icons.label_outline,
              label: label.name,
              onTap: () => choose(LabelFeed(label.id)),
            ),
          if (labels.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
              child: Text(
                'Make a label to show only its notes here.',
                style: AppText.ui.copyWith(
                  color: Theme.of(context).colors.inkMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
