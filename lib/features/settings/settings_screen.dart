import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:notes/core/theme/app_colors.dart';
import 'package:notes/core/theme/tokens.dart';
import 'package:notes/core/theme/typography.dart';
import 'package:notes/core/ui/undo.dart';
import 'package:notes/core/util/app_version.dart';
import 'package:notes/data/backup/bundle.dart';
import 'package:notes/data/device/home_widgets.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/domain/model/settings.dart';
import 'package:notes/features/settings/backup_sheets.dart';
import 'package:notes/features/settings/settings_rows.dart';
import 'package:notes/features/settings/theme_swatches.dart';
import 'package:notes/features/settings/widget_feed_sheet.dart';

/// The app's few settings, and the way notes leave the phone and come back.
///
/// Each choice applies the moment it is made; there is nothing to save.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _rebuilding = false;

  Future<void> _import() async {
    final picker = ref.read(documentPickerProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await picker.open(
        mimeTypes: const [
          Bundle.mimeType,
          'application/x-zip-compressed',
          'application/octet-stream',
        ],
      );
      if (file == null || !mounted) return;
      await showImportSheet(
        context,
        file: file,
        onChooseAnother: () => unawaited(_import()),
      );
    } on PlatformException catch (error) {
      debugPrint('The file could not be opened: $error');
      showMessage(messenger, 'That file could not be opened');
    }
  }

  /// Asks what the widget shows, then hands it to the launcher to place.
  Future<void> _addNotesWidget() async {
    final widgets = ref.read(homeWidgetsProvider);
    final feed = await showWidgetFeedSheet(context);
    if (feed != null) await widgets.pin(HomeWidget.notes, feed: feed);
  }

  Future<void> _rebuildIndex() async {
    final search = ref.read(searchRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _rebuilding = true);
    try {
      await search.rebuildIndex();
      showMessage(messenger, 'Search index rebuilt');
    } finally {
      if (mounted) setState(() => _rebuilding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    final settings =
        ref.watch(appSettingsProvider).value ?? const AppSettings();
    final repository = ref.read(settingsRepositoryProvider);
    // Offered only where the launcher can place a widget for the app; the
    // widgets are in the launcher's own list everywhere.
    final canPin = ref.watch(widgetPinningProvider).value ?? false;
    final widgets = ref.read(homeWidgetsProvider);

    return Scaffold(
      backgroundColor: colors.ground,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.only(
            bottom: Gap.xxl + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Gap.xs,
                Gap.lg,
                Gap.xs,
                Gap.sm,
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.arrow_back, color: colors.ink),
                  ),
                  const SizedBox(width: Gap.xs),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        'Settings',
                        style: AppText.display.copyWith(color: colors.ink),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SettingsHeader('THEME'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
              child: ThemeSwatches(
                current: settings.theme,
                onChanged: (theme) => unawaited(repository.setTheme(theme)),
              ),
            ),
            const SettingsHeader('CHECKED LIST ITEMS'),
            RadioGroup<CheckedItems>(
              groupValue: settings.checkedItems,
              onChanged: (value) {
                if (value != null) unawaited(repository.setCheckedItems(value));
              },
              child: Column(
                children: [
                  for (final choice in CheckedItems.values)
                    _Choice<CheckedItems>(
                      value: choice,
                      label: choice.label,
                      detail: choice.detail,
                    ),
                ],
              ),
            ),
            const SettingsHeader('TRASH'),
            const _Intro('Notes in the trash are deleted for good after'),
            RadioGroup<TrashRetention>(
              groupValue: settings.trashRetention,
              onChanged: (value) {
                if (value != null) {
                  unawaited(repository.setTrashRetention(value));
                }
              },
              child: Column(
                children: [
                  for (final choice in TrashRetention.values)
                    _Choice<TrashRetention>(value: choice, label: choice.label),
                ],
              ),
            ),
            const _Intro(
              'The trash is checked each time the app starts.',
              muted: true,
            ),
            if (canPin) ...[
              const SettingsHeader('HOME SCREEN'),
              SettingsAction(
                icon: Icons.view_agenda_outlined,
                label: 'Add the notes widget',
                detail: 'Every note, the pinned ones, or one label’s',
                onTap: () => unawaited(_addNotesWidget()),
              ),
              SettingsAction(
                icon: Icons.edit_outlined,
                label: 'Add the new note widget',
                detail: 'A note, a list, or a photo in one tap',
                onTap: () => unawaited(widgets.pin(HomeWidget.capture)),
              ),
            ],
            const SettingsHeader('BACKUP'),
            SettingsAction(
              icon: Icons.upload_file_outlined,
              label: 'Export notes',
              detail: 'Every note, label, and image, in one file',
              onTap: () => unawaited(showExportSheet(context)),
            ),
            SettingsAction(
              icon: Icons.download_outlined,
              label: 'Import notes',
              detail: 'From a file made with Export notes',
              onTap: () => unawaited(_import()),
            ),
            const SettingsHeader('SEARCH'),
            SettingsAction(
              icon: Icons.manage_search,
              label: 'Rebuild search index',
              detail: _rebuilding
                  ? 'Rebuilding…'
                  : 'For when search misses a note you know is there',
              onTap: _rebuilding ? null : () => unawaited(_rebuildIndex()),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.xxl, Gap.xl, 0),
              child: Text(
                'NOTES ${appVersion.toUpperCase()} · KEPT ON THIS DEVICE',
                style: AppText.meta.copyWith(color: colors.inkMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro(this.text, {this.muted = false});

  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(Gap.xl, muted ? Gap.xs : 0, Gap.xl, Gap.xs),
      child: Text(
        text,
        style: AppText.ui.copyWith(color: muted ? colors.inkMuted : colors.ink),
      ),
    );
  }
}

class _Choice<T> extends StatelessWidget {
  const _Choice({required this.value, required this.label, this.detail});

  final T value;
  final String label;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    final detail = this.detail;
    return RadioListTile<T>(
      value: value,
      contentPadding: const EdgeInsets.symmetric(horizontal: Gap.md),
      title: Text(label, style: AppText.uiLarge.copyWith(color: colors.ink)),
      subtitle: detail == null
          ? null
          : Text(detail, style: AppText.ui.copyWith(color: colors.inkMuted)),
    );
  }
}
