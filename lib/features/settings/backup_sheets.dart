import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:notes/core/theme/app_colors.dart';
import 'package:notes/core/theme/tokens.dart';
import 'package:notes/core/theme/typography.dart';
import 'package:notes/core/ui/undo.dart';
import 'package:notes/data/backup/bundle.dart';
import 'package:notes/data/backup/import_plan.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/data/repository/backup_repository.dart';
import 'package:path/path.dart' as p;

/// Writes an export as the sheet opens, then offers to save or share it.
Future<void> showExportSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const ExportSheet(),
    );

/// Reads [file] as the sheet opens and shows what importing it would do.
/// [onChooseAnother] opens the picker again, for a file that cannot be
/// imported.
Future<void> showImportSheet(
  BuildContext context, {
  required File file,
  required VoidCallback onChooseAnother,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => ImportSheet(file: file, onChooseAnother: onChooseAnother),
);

class ExportSheet extends ConsumerStatefulWidget {
  const ExportSheet({super.key});

  @override
  ConsumerState<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<ExportSheet> {
  late Future<({File file, Bundle bundle})> _export;

  /// True while the save picker or the share sheet is up.
  bool _handing = false;

  /// Images added to the file so far.
  ({int done, int total})? _progress;

  @override
  void initState() {
    super.initState();
    _export = _start();
  }

  Future<({File file, Bundle bundle})> _start() => ref
      .read(backupRepositoryProvider)
      .export(
        onProgress: (done, total) {
          if (mounted) setState(() => _progress = (done: done, total: total));
        },
      );

  void _retry() => setState(() {
    _progress = null;
    _export = _start();
  });

  Future<void> _save(File file) async {
    final picker = ref.read(documentPickerProvider);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _handing = true);
    try {
      final saved = await picker.save(
        file,
        name: p.basename(file.path),
        mimeType: Bundle.mimeType,
      );
      if (!saved) return;
      if (mounted) navigator.pop();
      showMessage(messenger, 'Export saved');
    } on PlatformException {
      showMessage(messenger, 'The export could not be saved there');
    } finally {
      if (mounted) setState(() => _handing = false);
    }
  }

  Future<void> _share(File file) async {
    final picker = ref.read(documentPickerProvider);
    final navigator = Navigator.of(context);
    setState(() => _handing = true);
    try {
      await picker.share(
        file,
        name: p.basename(file.path),
        mimeType: Bundle.mimeType,
      );
      if (mounted) navigator.pop();
    } finally {
      if (mounted) setState(() => _handing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _export,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('Export failed: ${snapshot.error}');
          return _SheetFrame(
            eyebrow: 'EXPORT',
            title: 'The export was not written',
            children: [
              const _Body(
                'Nothing was saved. Check that the phone has some storage '
                'free, then try again.',
              ),
              const SizedBox(height: Gap.xl),
              FilledButton(onPressed: _retry, child: const Text('Try again')),
            ],
          );
        }
        final export = snapshot.data;
        if (export == null) {
          return _SheetFrame(
            eyebrow: 'EXPORT',
            title: 'Export notes',
            children: [
              _imagesWorking(
                progress: _progress,
                before: 'Writing every note and label…',
                during: 'Adding images',
                after: 'Finishing the file…',
              ),
            ],
          );
        }

        final bundle = export.bundle;
        return _SheetFrame(
          eyebrow:
              '${p.basename(export.file.path).toUpperCase()} · '
              '${_size(export.file.lengthSync())}',
          title: 'Export notes',
          children: [
            const _Body(
              'One file with every note, including the archive and the '
              'trash, and their labels and images. Keep it somewhere off '
              'this phone.',
            ),
            const SizedBox(height: Gap.lg),
            _Ledger(
              lines: [
                (
                  count: '${bundle.notes.length}',
                  label: _noun(bundle.notes.length, 'note'),
                ),
                (
                  count: '${bundle.labels.length}',
                  label: _noun(bundle.labels.length, 'label'),
                ),
                (
                  count: '${bundle.imageCount}',
                  label: _noun(bundle.imageCount, 'image'),
                ),
              ],
            ),
            if (bundle.missingImages > 0) ...[
              const SizedBox(height: Gap.md),
              _Warning(
                '${_plural(bundle.missingImages, 'image')} could not be '
                'found on this phone and '
                '${bundle.missingImages == 1 ? 'is' : 'are'} left out.',
              ),
            ],
            const SizedBox(height: Gap.xl),
            FilledButton.icon(
              onPressed: _handing ? null : () => unawaited(_save(export.file)),
              icon: const Icon(Icons.save_alt),
              label: const Text('Save to a file'),
            ),
            const SizedBox(height: Gap.sm),
            TextButton.icon(
              onPressed: _handing ? null : () => unawaited(_share(export.file)),
              icon: const Icon(Icons.share_outlined),
              label: const Text('Share'),
            ),
          ],
        );
      },
    );
  }
}

class ImportSheet extends ConsumerStatefulWidget {
  const ImportSheet({
    required this.file,
    required this.onChooseAnother,
    super.key,
  });

  final File file;
  final VoidCallback onChooseAnother;

  @override
  ConsumerState<ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends ConsumerState<ImportSheet> {
  late final Future<ImportPreview> _reading = ref
      .read(backupRepositoryProvider)
      .preview(widget.file);
  ImportMode _mode = ImportMode.merge;
  bool _importing = false;
  bool _failed = false;

  /// Images unpacked so far while importing.
  ({int done, int total})? _progress;

  Future<void> _import(ImportPreview preview) async {
    final repository = ref.read(backupRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final mode = _mode;
    if (mode == ImportMode.replace &&
        !await confirmReplace(context, preview.replace)) {
      return;
    }

    setState(() {
      _importing = true;
      _failed = false;
      _progress = null;
    });
    try {
      final plan = await repository.import(
        preview,
        mode,
        onProgress: (done, total) {
          if (mounted) setState(() => _progress = (done: done, total: total));
        },
      );
      // The sheet may have been swiped away meanwhile; the import still ran.
      if (mounted) navigator.pop();
      final notes = plan.notesAdded + plan.notesUpdated;
      showMessage(
        messenger,
        mode == ImportMode.replace
            ? 'Notes replaced'
            : notes == 0
            ? 'Labels imported'
            : '${_plural(notes, 'note')} imported',
      );
    } on Object catch (error) {
      debugPrint('Import failed: $error');
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _chooseAnother() {
    Navigator.of(context).pop();
    widget.onChooseAnother();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_importing,
      child: FutureBuilder(
        future: _reading,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _problem(snapshot.error);
          }
          final preview = snapshot.data;
          if (preview == null) {
            return const _SheetFrame(
              eyebrow: 'IMPORT',
              title: 'Import notes',
              children: [_Working('Reading the file…')],
            );
          }
          return _previewOf(preview);
        },
      ),
    );
  }

  Widget _problem(Object? error) {
    final problem = error is BundleException
        ? error.problem
        : BundleProblem.notAnExport;
    if (error is! BundleException) debugPrint('Import read failed: $error');
    final (title, body) = switch (problem) {
      BundleProblem.notAnExport => (
        'This file is not a Notes export',
        'Choose a .zip file made with Export notes.',
      ),
      BundleProblem.newerVersion => (
        'This export is from a newer version of Notes',
        'Update the app, then import the file again. Nothing was changed.',
      ),
      BundleProblem.damaged => (
        'This export is damaged',
        'Part of it cannot be read, so nothing was imported. Try another '
            'copy of the export.',
      ),
    };
    return _SheetFrame(
      eyebrow: 'CANNOT IMPORT',
      title: title,
      children: [
        _Body(body),
        const SizedBox(height: Gap.xl),
        FilledButton(
          onPressed: _chooseAnother,
          child: const Text('Choose another file'),
        ),
      ],
    );
  }

  Widget _previewOf(ImportPreview preview) {
    final colors = Theme.of(context).colors;
    final bundle = preview.bundle;
    final plan = preview.planFor(_mode);
    final exportedAt = bundle.exportedAt;
    final nothingNew =
        _mode == ImportMode.merge &&
        plan.notesAdded == 0 &&
        plan.notesUpdated == 0 &&
        plan.labelsAdded == 0;

    return _SheetFrame(
      eyebrow: [
        if (exportedAt != null)
          'EXPORTED ${DateFormat('d MMM y, HH:mm').format(exportedAt).toUpperCase()}',
        if (bundle.appVersion.isNotEmpty) 'VERSION ${bundle.appVersion}',
      ].join(' · '),
      title: '${_plural(bundle.notes.length, 'note')} in this file',
      children: [
        RadioGroup<ImportMode>(
          groupValue: _mode,
          onChanged: (mode) {
            if (_importing || mode == null) return;
            setState(() => _mode = mode);
          },
          child: const Column(
            children: [
              _Choice(
                value: ImportMode.merge,
                label: 'Merge with the notes here',
                detail:
                    'A note on both keeps its latest edit. Nothing here is '
                    'deleted.',
              ),
              _Choice(
                value: ImportMode.replace,
                label: 'Replace the notes here',
                detail: 'Every note and label on this phone is deleted first.',
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.lg),
        if (nothingNew)
          const _Body('Every note in this file is here already.')
        else
          _Ledger(
            lines: [
              if (_mode == ImportMode.replace && plan.notesRemoved > 0)
                (
                  count: '−${plan.notesRemoved}',
                  label: '${_noun(plan.notesRemoved, 'note')} here deleted',
                ),
              if (plan.notesAdded > 0)
                (
                  count: '+${plan.notesAdded}',
                  label: _mode == ImportMode.replace
                      ? '${_noun(plan.notesAdded, 'note')} from the file'
                      : 'new ${_noun(plan.notesAdded, 'note')}',
                ),
              if (plan.notesUpdated > 0)
                (
                  count: '${plan.notesUpdated}',
                  label:
                      '${_noun(plan.notesUpdated, 'note')} updated to a later '
                      'edit',
                ),
              if (plan.notesKept > 0)
                (
                  count: '${plan.notesKept}',
                  label:
                      '${_noun(plan.notesKept, 'note')} kept, edited here '
                      'since',
                ),
              if (plan.labelsAdded > 0)
                (
                  count: '+${plan.labelsAdded}',
                  label: _noun(plan.labelsAdded, 'label'),
                ),
              if (plan.imagesAdded > 0)
                (
                  count: '+${plan.imagesAdded}',
                  label: _noun(plan.imagesAdded, 'image'),
                ),
            ],
          ),
        if (plan.imagesMissing > 0) ...[
          const SizedBox(height: Gap.md),
          _Warning(
            '${_plural(plan.imagesMissing, 'image')} the notes list '
            '${plan.imagesMissing == 1 ? 'is' : 'are'} not in the file and '
            '${plan.imagesMissing == 1 ? 'is' : 'are'} left out.',
          ),
        ],
        if (_failed) ...[
          const SizedBox(height: Gap.md),
          const _Warning(
            'The import did not finish, and nothing was changed. Try again.',
          ),
        ],
        const SizedBox(height: Gap.xl),
        if (_importing)
          _imagesWorking(
            progress: _progress,
            before: 'Importing…',
            during: 'Unpacking images',
            after: 'Saving notes…',
          )
        else if (_mode == ImportMode.replace)
          FilledButton(
            onPressed: () => unawaited(_import(preview)),
            style: FilledButton.styleFrom(
              backgroundColor: colors.danger,
              foregroundColor: colors.onAccent,
            ),
            child: const Text('Replace notes'),
          )
        else
          FilledButton(
            onPressed: nothingNew ? null : () => unawaited(_import(preview)),
            child: const Text('Import'),
          ),
      ],
    );
  }
}

/// Asks for "replace" to be typed before every note here is deleted.
Future<bool> confirmReplace(BuildContext context, ImportPlan plan) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => _ReplaceDialog(plan: plan),
  );
  return confirmed ?? false;
}

class _ReplaceDialog extends StatefulWidget {
  const _ReplaceDialog({required this.plan});

  final ImportPlan plan;

  @override
  State<_ReplaceDialog> createState() => _ReplaceDialogState();
}

class _ReplaceDialogState extends State<_ReplaceDialog> {
  static const _word = 'replace';
  final _typed = TextEditingController();

  bool get _matches => _typed.text.trim().toLowerCase() == _word;

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    final plan = widget.plan;
    final here = plan.notesRemoved;

    return AlertDialog(
      scrollable: true,
      title: const Text('Replace every note here?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${here == 1 ? 'The 1 note' : 'The $here notes'} on this phone, '
            'with their labels and images, will be deleted, and the '
            '${_plural(plan.notesAdded, 'note')} in the file take their '
            'place. This cannot be undone.',
          ),
          const SizedBox(height: Gap.lg),
          TextField(
            controller: _typed,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (_matches) Navigator.of(context).pop(true);
            },
            style: AppText.uiLarge.copyWith(color: colors.ink),
            decoration: InputDecoration(
              labelText: 'Type “$_word” to confirm',
              labelStyle: AppText.ui.copyWith(color: colors.inkMuted),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: colors.hairline),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: colors.danger),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _matches ? () => Navigator.of(context).pop(true) : null,
          style: TextButton.styleFrom(foregroundColor: colors.danger),
          child: const Text('Replace notes'),
        ),
      ],
    );
  }
}

String _noun(int count, String noun) => count == 1 ? noun : '${noun}s';

String _plural(int count, String noun) => '$count ${_noun(count, noun)}';

String _size(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// A sheet's layout: a meta eyebrow, a title, and what follows.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.eyebrow,
    required this.title,
    required this.children,
  });

  final String eyebrow;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        Gap.xl,
        0,
        Gap.xl,
        Gap.xl + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            eyebrow,
            style: AppText.metaStrong.copyWith(color: colors.inkMuted),
          ),
          const SizedBox(height: Gap.sm),
          Semantics(
            header: true,
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          const SizedBox(height: Gap.md),
          ...children,
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppText.ui.copyWith(color: Theme.of(context).colors.inkMuted),
  );
}

class _Warning extends StatelessWidget {
  const _Warning(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppText.ui.copyWith(color: Theme.of(context).colors.danger),
  );
}

/// Work under way: what is happening, over a thin running line.
class _Working extends StatelessWidget {
  const _Working(this.text, {this.progress});

  final String text;

  /// Images done of all of them, once there are images to count. Without it
  /// the line runs without saying how far along the work is.
  final ({int done, int total})? progress;

  @override
  Widget build(BuildContext context) {
    final progress = this.progress;
    final counted = progress != null && progress.total > 0;
    final of = counted ? '${progress.done} of ${progress.total}' : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The step is announced when it changes; the count is left to the
        // bar, so a screen reader is not read every image.
        Semantics(liveRegion: true, child: _Body(text)),
        const SizedBox(height: Gap.md),
        LinearProgressIndicator(
          value: counted ? progress.done / progress.total : null,
          semanticsLabel: text,
          semanticsValue: of,
        ),
        if (of != null) ...[
          const SizedBox(height: Gap.xs),
          ExcludeSemantics(
            child: Text(
              of.toUpperCase(),
              style: AppText.meta.copyWith(
                color: Theme.of(context).colors.inkMuted,
              ),
            ),
          ),
        ],
        const SizedBox(height: Gap.lg),
      ],
    );
  }
}

/// What the progress of images being copied reads as, once there are any:
/// the images, then whatever comes after them.
_Working _imagesWorking({
  required ({int done, int total})? progress,
  required String before,
  required String during,
  required String after,
}) {
  if (progress == null || progress.total == 0) return _Working(before);
  if (progress.done >= progress.total) return _Working(after);
  return _Working(during, progress: progress);
}

/// Counts in a column of mono figures, each with what it counts.
class _Ledger extends StatelessWidget {
  const _Ledger({required this.lines});

  final List<({String count, String label})> lines;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    final figures = MediaQuery.textScalerOf(context).scale(56);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.hairline),
          bottom: BorderSide(color: colors.hairline),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.sm),
        child: Column(
          children: [
            for (final line in lines)
              MergeSemantics(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      SizedBox(
                        width: figures,
                        child: Text(
                          line.count,
                          textAlign: TextAlign.right,
                          style: AppText.metaStrong.copyWith(
                            color: line.count.startsWith('−')
                                ? colors.danger
                                : colors.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: Gap.md),
                      Expanded(
                        child: Text(
                          line.label,
                          style: AppText.ui.copyWith(color: colors.ink),
                        ),
                      ),
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

class _Choice extends StatelessWidget {
  const _Choice({
    required this.value,
    required this.label,
    required this.detail,
  });

  final ImportMode value;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    return RadioListTile<ImportMode>(
      value: value,
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      title: Text(label, style: AppText.uiLarge.copyWith(color: colors.ink)),
      subtitle: Text(
        detail,
        style: AppText.ui.copyWith(color: colors.inkMuted),
      ),
    );
  }
}
