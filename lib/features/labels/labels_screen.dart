import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:notes/core/theme/app_colors.dart';
import 'package:notes/core/theme/tokens.dart';
import 'package:notes/core/theme/typography.dart';
import 'package:notes/core/ui/undo.dart';
import 'package:notes/core/util/reorder.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/data/repository/label_repository.dart';
import 'package:notes/domain/model/label.dart';
import 'package:notes/features/labels/label_providers.dart';

/// Make, rename, reorder, and delete labels. The order set here is the order
/// of the drawer and of every list of labels.
class LabelsScreen extends ConsumerStatefulWidget {
  const LabelsScreen({super.key});

  @override
  ConsumerState<LabelsScreen> createState() => _LabelsScreenState();
}

class _LabelsScreenState extends ConsumerState<LabelsScreen> {
  final _newName = TextEditingController();

  @override
  void dispose() {
    _newName.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final repository = ref.read(labelRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final name = LabelRepository.cleanName(_newName.text);
    if (name == null) return;

    final before = ref.read(labelsProvider).value ?? const <Label>[];
    final label = await repository.create(name);
    _newName.clear();
    if (before.any((existing) => existing.id == label.id)) {
      showMessage(messenger, '“${label.name}” is already a label');
    }
    if (mounted) setState(() {});
  }

  void _move(List<Label> labels, int from, int to) {
    final bounds = neighboursForMove(
      [for (final label in labels) label.sortKey],
      from: from,
      to: to,
    );
    if (bounds == null) return;
    unawaited(
      ref
          .read(labelRepositoryProvider)
          .reorder(labels[from].id, prevKey: bounds.prev, nextKey: bounds.next),
    );
  }

  /// Deletes at once, with undo, as deleting a note does. The notes that
  /// wore the label are untouched either way.
  Future<void> _delete(Label label) async {
    final repository = ref.read(labelRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final deleted = await repository.delete(label.id);
    showUndo(
      messenger,
      message: 'Label deleted',
      onUndo: () => repository.restore(deleted),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    final labelsAsync = ref.watch(labelsProvider);
    final labels = labelsAsync.value ?? const <Label>[];
    final typed = LabelRepository.cleanName(_newName.text);

    return Scaffold(
      backgroundColor: colors.ground,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
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
                          'Labels',
                          style: AppText.display.copyWith(color: colors.ink),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Gap.sm, 0, Gap.xs, 0),
                child: Row(
                  children: [
                    SizedBox(
                      width: 48,
                      child: Icon(Icons.add, color: colors.accent),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _newName,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => unawaited(_create()),
                        textInputAction: TextInputAction.done,
                        textCapitalization: TextCapitalization.sentences,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(
                            LabelRepository.maxLength,
                          ),
                        ],
                        style: AppText.uiLarge.copyWith(color: colors.ink),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: Gap.md,
                          ),
                          hintText: 'New label',
                          hintStyle: AppText.uiLarge.copyWith(
                            color: colors.inkMuted,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Create label',
                      onPressed: typed == null
                          ? null
                          : () => unawaited(_create()),
                      icon: Icon(
                        Icons.check,
                        color: typed == null ? colors.hairline : colors.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: Divider()),
            if (labelsAsync.hasValue && labels.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(Gap.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NO LABELS YET',
                        style: AppText.metaStrong.copyWith(
                          color: colors.inkMuted,
                        ),
                      ),
                      const SizedBox(height: Gap.md),
                      Text(
                        'A label gathers notes from any day and any colour '
                        'under one name. Name one above.',
                        style: AppText.noteBody.copyWith(
                          color: colors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.only(
                  top: Gap.xs,
                  bottom: Gap.xxl + MediaQuery.paddingOf(context).bottom,
                ),
                sliver: SliverReorderableList(
                  itemCount: labels.length,
                  onReorderItem: (from, to) => _move(labels, from, to),
                  proxyDecorator: (child, index, animation) => Material(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(Radii.small),
                    child: child,
                  ),
                  itemBuilder: (context, index) {
                    final label = labels[index];
                    return _LabelRow(
                      key: ValueKey(label.id),
                      label: label,
                      index: index,
                      onDelete: () => unawaited(_delete(label)),
                      onMoveUp: index > 0
                          ? () => _move(labels, index, index - 1)
                          : null,
                      onMoveDown: index < labels.length - 1
                          ? () => _move(labels, index, index + 1)
                          : null,
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

/// One label: a handle to drag it, its name to edit in place, and delete.
class _LabelRow extends ConsumerStatefulWidget {
  const _LabelRow({
    required this.label,
    required this.index,
    required this.onDelete,
    this.onMoveUp,
    this.onMoveDown,
    super.key,
  });

  final Label label;
  final int index;
  final VoidCallback onDelete;

  /// Moves for screen readers, which cannot drag. Null at either end.
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  ConsumerState<_LabelRow> createState() => _LabelRowState();
}

class _LabelRowState extends ConsumerState<_LabelRow> {
  static const _moveUp = CustomSemanticsAction(label: 'Move up');
  static const _moveDown = CustomSemanticsAction(label: 'Move down');

  late final LabelRepository _repository;
  late final TextEditingController _name;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _repository = ref.read(labelRepositoryProvider);
    _name = TextEditingController(text: widget.label.name);
    _focus.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _LabelRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A saved or undone rename shows here, unless a new one is being typed.
    if (!_focus.hasFocus && _name.text != widget.label.name) {
      _name.text = widget.label.name;
    }
  }

  @override
  void dispose() {
    // Leaving the page in the middle of a rename still keeps the new name.
    if (_name.text != widget.label.name) {
      unawaited(_repository.rename(widget.label.id, _name.text));
    }
    _focus
      ..removeListener(_onFocusChanged)
      ..dispose();
    _name.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focus.hasFocus) unawaited(_commit());
  }

  Future<void> _commit() async {
    final typed = _name.text;
    if (typed == widget.label.name) return;
    final messenger = ScaffoldMessenger.of(context);
    final result = await _repository.rename(widget.label.id, typed);
    if (result == RenameResult.renamed || !mounted) return;

    // Refused or tidied to the same name: put the saved name back.
    _name.text = widget.label.name;
    if (result == RenameResult.taken) {
      showMessage(
        messenger,
        '“${LabelRepository.cleanName(typed)}” is already a label',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;

    return Semantics(
      container: true,
      customSemanticsActions: {
        _moveUp: ?widget.onMoveUp,
        _moveDown: ?widget.onMoveDown,
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: widget.index,
              child: Semantics(
                label: 'Drag to reorder',
                child: SizedBox(
                  width: 48,
                  height: 52,
                  child: Icon(Icons.drag_indicator, color: colors.inkMuted),
                ),
              ),
            ),
            Expanded(
              child: TextField(
                controller: _name,
                focusNode: _focus,
                textInputAction: TextInputAction.done,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(LabelRepository.maxLength),
                ],
                onSubmitted: (_) => _focus.unfocus(),
                style: AppText.uiLarge.copyWith(color: colors.ink),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: Gap.md),
                  enabledBorder: InputBorder.none,
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: colors.accent),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Delete “${widget.label.name}”',
              onPressed: widget.onDelete,
              icon: Icon(Icons.delete_outline, color: colors.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}
