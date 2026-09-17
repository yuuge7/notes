import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:notes/core/theme/app_colors.dart';
import 'package:notes/core/theme/tokens.dart';
import 'package:notes/core/theme/typography.dart';
import 'package:notes/core/util/search_text.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/data/repository/label_repository.dart';
import 'package:notes/domain/model/label.dart';
import 'package:notes/features/labels/label_providers.dart';
import 'package:notes/features/notes/widgets/notes_states.dart';

/// Opens the page for choosing the labels on [noteIds]. Every tap applies at
/// once, so there is nothing to confirm on the way out.
Future<void> showLabelPicker(
  BuildContext context, {
  required List<String> noteIds,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(builder: (_) => LabelPicker(noteIds: noteIds)),
);

/// Labels for one note, or for several selected at once.
///
/// The field at the top both filters the list and names a new label, so
/// finding a label and making one are the same gesture.
class LabelPicker extends ConsumerStatefulWidget {
  const LabelPicker({required this.noteIds, super.key});

  final List<String> noteIds;

  @override
  ConsumerState<LabelPicker> createState() => _LabelPickerState();
}

class _LabelPickerState extends ConsumerState<LabelPicker> {
  final _field = TextEditingController();
  late final LabelRepository _labels = ref.read(labelRepositoryProvider);
  late final Stream<Map<String, int>> _usage = _labels.watchUsage(
    widget.noteIds,
  );

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _create(String name) async {
    final label = await _labels.create(name);
    await _labels.setOnNotes(widget.noteIds, label.id, on: true);
    _field.clear();
    if (mounted) setState(() {});
  }

  /// A label on none or only some of the notes goes on all of them; one on
  /// all of them comes off.
  Future<void> _toggle(Label label, {required bool? onAll}) =>
      _labels.setOnNotes(widget.noteIds, label.id, on: onAll != true);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    final labelsAsync = ref.watch(labelsProvider);
    final all = labelsAsync.value ?? const <Label>[];
    final typed = LabelRepository.cleanName(_field.text);
    final filter = SearchText.fold(typed ?? '');
    final shown = [
      for (final label in all)
        if (SearchText.fold(label.name).contains(filter)) label,
    ];
    final exists =
        typed != null &&
        all.any((label) => SearchText.fold(label.name) == filter);
    final count = widget.noteIds.length;

    return Scaffold(
      backgroundColor: colors.ground,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.xs, Gap.sm, Gap.xs, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.arrow_back, color: colors.ink),
                  ),
                  const SizedBox(width: Gap.xs),
                  Expanded(
                    child: TextField(
                      controller: _field,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) {
                        if (typed != null && !exists) {
                          unawaited(_create(typed));
                        }
                      },
                      textInputAction: TextInputAction.done,
                      textCapitalization: TextCapitalization.sentences,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(
                          LabelRepository.maxLength,
                        ),
                      ],
                      textAlignVertical: TextAlignVertical.center,
                      style: AppText.uiLarge.copyWith(color: colors.ink),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: Gap.md,
                        ),
                        constraints: const BoxConstraints(
                          minHeight: Layout.minTouch,
                        ),
                        hintText: 'Find or make a label',
                        hintStyle: AppText.uiLarge.copyWith(
                          color: colors.inkMuted,
                        ),
                      ),
                    ),
                  ),
                  if (_field.text.isNotEmpty)
                    IconButton(
                      tooltip: 'Clear',
                      onPressed: () => setState(_field.clear),
                      icon: Icon(Icons.close, color: colors.inkMuted),
                    ),
                ],
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Gap.xl,
                Gap.lg,
                Gap.xl,
                Gap.xs,
              ),
              child: Text(
                count == 1 ? 'LABELS ON THIS NOTE' : 'LABELS ON $count NOTES',
                style: AppText.metaStrong.copyWith(color: colors.inkMuted),
              ),
            ),
            Expanded(
              child: StreamBuilder<Map<String, int>>(
                stream: _usage,
                builder: (context, snapshot) {
                  final usage = snapshot.data ?? const <String, int>{};
                  if (labelsAsync.hasError && !labelsAsync.hasValue) {
                    return NotesError(
                      eyebrow: 'LABELS DID NOT LOAD',
                      detail: '${labelsAsync.error}',
                      onRetry: () => ref.invalidate(labelsProvider),
                    );
                  }
                  if (!labelsAsync.hasValue) return const RowsSkeleton();
                  return ListView(
                    padding: EdgeInsets.only(
                      bottom: Gap.xl + MediaQuery.paddingOf(context).bottom,
                    ),
                    children: [
                      if (typed != null && !exists)
                        _CreateRow(
                          name: typed,
                          onTap: () => unawaited(_create(typed)),
                        ),
                      for (final label in shown)
                        _PickRow(
                          label: label,
                          onAll: switch (usage[label.id] ?? 0) {
                            0 => false,
                            final wearing when wearing >= count => true,
                            _ => null,
                          },
                          onTap: (onAll) =>
                              unawaited(_toggle(label, onAll: onAll)),
                        ),
                      if (all.isEmpty && typed == null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            Gap.xl,
                            Gap.sm,
                            Gap.xl,
                            0,
                          ),
                          child: Text(
                            'A label gathers notes from any day and any '
                            'colour under one name. Type a name above to '
                            'make the first.',
                            style: AppText.noteBody.copyWith(
                              color: colors.inkMuted,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.label,
    required this.onAll,
    required this.onTap,
  });

  final Label label;

  /// Whether every note wears the label: true for all, false for none, null
  /// for some.
  final bool? onAll;
  final ValueChanged<bool?> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    return MergeSemantics(
      child: InkWell(
        onTap: () => onTap(onAll),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.only(left: Gap.xl, right: Gap.md),
            child: Row(
              children: [
                Icon(Icons.label_outline, size: 20, color: colors.inkMuted),
                const SizedBox(width: Gap.lg),
                Expanded(
                  child: Text(
                    label.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.uiLarge.copyWith(color: colors.ink),
                  ),
                ),
                Checkbox(
                  value: onAll,
                  tristate: true,
                  onChanged: (_) => onTap(onAll),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateRow extends StatelessWidget {
  const _CreateRow({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
          child: Row(
            children: [
              Icon(Icons.add, size: 20, color: colors.accent),
              const SizedBox(width: Gap.lg),
              Expanded(
                child: Text(
                  'Create “$name”',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.uiLargeStrong.copyWith(color: colors.accent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
