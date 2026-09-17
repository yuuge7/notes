import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:notes/core/theme/app_colors.dart';
import 'package:notes/core/theme/tokens.dart';
import 'package:notes/core/theme/typography.dart';
import 'package:notes/core/ui/undo.dart';
import 'package:notes/data/db/note_dao.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/domain/model/note.dart';
import 'package:notes/features/editor/pigment_sheet.dart';
import 'package:notes/features/labels/label_picker.dart';
import 'package:notes/features/notes/selection.dart';

/// Takes the place of a shelf's header while notes are selected: a count, and
/// the actions that apply to all of them at once. Every action can be undone.
class SelectionBar extends ConsumerWidget {
  const SelectionBar({required this.shelf, required this.notes, super.key});

  final Shelf shelf;

  /// Every note on the shelf. The selected ones are read from here so undo
  /// can put back each note's own previous state.
  final List<Note> notes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colors;
    final selectedIds = ref.watch(noteSelectionProvider(shelf));
    final selected = notes
        .where((note) => selectedIds.contains(note.id))
        .toList();
    final count = selected.length;
    final allPinned = count > 0 && selected.every((note) => note.pinned);
    final onArchive = shelf == Shelf.archived;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.xs, Gap.md, Gap.xs, Gap.sm),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Clear selection',
            onPressed: () =>
                ref.read(noteSelectionProvider(shelf).notifier).clear(),
            icon: Icon(Icons.close, color: colors.ink),
          ),
          const SizedBox(width: Gap.xs),
          // The count alone: five actions and a close button leave a 360dp
          // phone no room for a word beside it.
          Expanded(
            child: Semantics(
              liveRegion: true,
              label: '$count selected',
              excludeSemantics: true,
              child: Text(
                '$count',
                maxLines: 1,
                style: AppText.displaySmall.copyWith(color: colors.ink),
              ),
            ),
          ),
          if (shelf == Shelf.active)
            IconButton(
              tooltip: allPinned ? 'Unpin' : 'Pin',
              onPressed: () =>
                  unawaited(_pin(context, ref, selected, pin: !allPinned)),
              icon: Icon(
                allPinned ? Icons.push_pin : Icons.push_pin_outlined,
                color: colors.ink,
              ),
            ),
          IconButton(
            tooltip: 'Labels',
            onPressed: () => unawaited(_label(context, ref, selected)),
            icon: Icon(Icons.label_outline, color: colors.ink),
          ),
          IconButton(
            tooltip: 'Colour',
            onPressed: () => unawaited(_recolour(context, ref, selected)),
            icon: Icon(Icons.palette_outlined, color: colors.ink),
          ),
          IconButton(
            tooltip: onArchive ? 'Unarchive' : 'Archive',
            onPressed: () => unawaited(
              _archive(context, ref, selected, archive: !onArchive),
            ),
            icon: Icon(
              onArchive ? Icons.unarchive_outlined : Icons.archive_outlined,
              color: colors.ink,
            ),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: () => unawaited(_delete(context, ref, selected)),
            icon: Icon(Icons.delete_outline, color: colors.ink),
          ),
        ],
      ),
    );
  }

  String _subject(int count) => count == 1 ? 'Note' : '$count notes';

  Future<void> _pin(
    BuildContext context,
    WidgetRef ref,
    List<Note> selected, {
    required bool pin,
  }) async {
    final repository = ref.read(noteRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final previous = {for (final note in selected) note.id: note.pinned};
    ref.read(noteSelectionProvider(shelf).notifier).clear();

    await repository.setPinnedMany(previous.keys, pinned: pin);
    showUndo(
      messenger,
      message: '${_subject(previous.length)} ${pin ? 'pinned' : 'unpinned'}',
      onUndo: () => repository.restorePinned(previous),
    );
  }

  /// Labels apply as they are ticked, so there is nothing to undo here: the
  /// same page takes them off again.
  Future<void> _label(
    BuildContext context,
    WidgetRef ref,
    List<Note> selected,
  ) async {
    final selection = ref.read(noteSelectionProvider(shelf).notifier);
    await showLabelPicker(
      context,
      noteIds: [for (final note in selected) note.id],
    );
    selection.clear();
  }

  Future<void> _recolour(
    BuildContext context,
    WidgetRef ref,
    List<Note> selected,
  ) async {
    final repository = ref.read(noteRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final selection = ref.read(noteSelectionProvider(shelf).notifier);
    final pigments = selected.map((note) => note.pigment).toSet();

    final picked = await showPigmentSheet(
      context,
      current: pigments.length == 1 ? pigments.first : null,
    );
    if (picked == null) return;

    final previous = {for (final note in selected) note.id: note.pigment};
    selection.clear();
    await repository.setPigmentMany(previous.keys, picked);
    showUndo(
      messenger,
      message: 'Colour changed',
      onUndo: () => repository.restorePigments(previous),
    );
  }

  Future<void> _archive(
    BuildContext context,
    WidgetRef ref,
    List<Note> selected, {
    required bool archive,
  }) async {
    final repository = ref.read(noteRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final ids = [for (final note in selected) note.id];
    ref.read(noteSelectionProvider(shelf).notifier).clear();

    await repository.setArchivedMany(ids, archived: archive);
    showUndo(
      messenger,
      message:
          '${_subject(ids.length)} ${archive ? 'archived' : 'unarchived'}',
      onUndo: () => repository.setArchivedMany(ids, archived: !archive),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    List<Note> selected,
  ) async {
    final repository = ref.read(noteRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final ids = [for (final note in selected) note.id];
    ref.read(noteSelectionProvider(shelf).notifier).clear();

    await repository.deleteMany(ids);
    showUndo(
      messenger,
      message: '${_subject(ids.length)} moved to trash',
      onUndo: () => repository.restoreMany(ids),
    );
  }
}
