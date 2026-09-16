import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';
import 'package:notes/core/theme/app_colors.dart';
import 'package:notes/core/theme/tokens.dart';
import 'package:notes/core/theme/typography.dart';
import 'package:notes/core/ui/shelf_scaffold.dart';
import 'package:notes/core/ui/undo.dart';
import 'package:notes/data/db/note_dao.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/domain/model/note.dart';
import 'package:notes/domain/model/settings.dart';
import 'package:notes/features/notes/notes_providers.dart';
import 'package:notes/features/notes/notes_screen.dart';
import 'package:notes/features/notes/selection.dart';
import 'package:notes/features/notes/widgets/app_drawer.dart';
import 'package:notes/features/notes/widgets/note_tile.dart';
import 'package:notes/features/notes/widgets/notes_states.dart';
import 'package:notes/features/notes/widgets/selection_bar.dart';

/// Archive and trash: the same cards, without capture and without the day
/// gutter — on these shelves what matters is what is kept, not when it was
/// written.
class ShelfScreen extends ConsumerWidget {
  const ShelfScreen({required this.shelf, super.key})
    : assert(shelf != Shelf.active, 'The active shelf is NotesScreen');

  final Shelf shelf;

  bool get _isTrash => shelf == Shelf.trash;

  String get _path => _isTrash ? '/trash' : '/archive';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(shelfNotesProvider(shelf));
    final selection = ref.watch(noteSelectionProvider(shelf));
    final layout = ref.watch(notesLayoutModeProvider);
    final columns = NotesScreen.columnsFor(layout);
    final notes = notesAsync.value ?? const <Note>[];
    final colors = Theme.of(context).colors;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final retention =
        ref.watch(appSettingsProvider).value?.trashRetention ??
        const AppSettings().trashRetention;

    final Widget content;
    if (notesAsync.isLoading && !notesAsync.hasValue) {
      content = NotesSkeleton(columns: columns);
    } else if (notesAsync.hasError) {
      content = NotesError(
        detail: '${notesAsync.error}',
        onRetry: () => ref.invalidate(shelfNotesProvider(shelf)),
      );
    } else if (notes.isEmpty) {
      content = _isTrash
          ? TrashEmpty(retention: retention)
          : const ArchiveEmpty();
    } else {
      content = MasonryGridView.count(
        padding: EdgeInsets.fromLTRB(
          Layout.contentRight,
          Gap.sm,
          Layout.contentRight,
          Gap.xxl + bottomInset,
        ),
        crossAxisCount: columns,
        mainAxisSpacing: Layout.cardGap,
        crossAxisSpacing: Layout.cardGap,
        itemCount: notes.length,
        itemBuilder: (context, index) {
          final note = notes[index];
          return RepaintBoundary(
            child: NoteTile(
              key: ValueKey(note.id),
              note: note,
              readOnly: _isTrash,
              selecting: selection.isNotEmpty,
              selected: selection.contains(note.id),
              onToggleSelected: _isTrash
                  ? null
                  : () => ref
                        .read(noteSelectionProvider(shelf).notifier)
                        .toggle(note.id),
            ),
          );
        },
      );
    }

    return ShelfScaffold(
      // Back closes the drawer, then clears a selection, then returns to the
      // grid rather than leaving the app from a secondary shelf.
      canPop: false,
      onBlockedPop: () {
        if (selection.isNotEmpty) {
          ref.read(noteSelectionProvider(shelf).notifier).clear();
        } else {
          context.go('/');
        }
      },
      drawer: AppDrawer(currentPath: _path),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (selection.isNotEmpty)
              SelectionBar(shelf: shelf, notes: notes)
            else
              ShelfHeader(
                title: _isTrash ? 'Trash' : 'Archive',
                count: notesAsync.value?.length,
                action: _isTrash && notes.isNotEmpty
                    ? TextButton(
                        onPressed: () =>
                            unawaited(_confirmEmptyTrash(context, ref)),
                        style: TextButton.styleFrom(
                          foregroundColor: colors.danger,
                        ),
                        child: const Text('Empty trash'),
                      )
                    : null,
              ),
            if (_isTrash && notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Layout.contentRight,
                  0,
                  Layout.contentRight,
                  Gap.sm,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'NOTES HERE ARE DELETED AFTER '
                    '${retention.label.toUpperCase()}',
                    style: AppText.meta.copyWith(color: colors.inkMuted),
                  ),
                ),
              ),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmEmptyTrash(BuildContext context, WidgetRef ref) async {
    final colors = Theme.of(context).colors;
    final repository = ref.read(noteRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Empty the trash?'),
        content: const Text(
          'Every note in the trash is removed from this device. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: colors.danger),
            child: const Text('Empty trash'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await repository.emptyTrash();
    showMessage(messenger, 'Trash emptied');
  }
}

class ShelfHeader extends StatelessWidget {
  const ShelfHeader({
    required this.title,
    required this.count,
    this.action,
    super.key,
  });

  final String title;
  final int? count;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.xs, Gap.lg, Gap.sm, Gap.sm),
      child: Row(
        children: [
          Builder(
            builder: (context) => IconButton(
              tooltip: 'Open menu',
              onPressed: () => Scaffold.of(context).openDrawer(),
              icon: Icon(Icons.menu, color: colors.ink),
            ),
          ),
          const SizedBox(width: Gap.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: AppText.display.copyWith(color: colors.ink),
                  ),
                ),
                const SizedBox(height: Gap.xs),
                SizedBox(
                  height: AppText.meta.fontSize! * AppText.meta.height!,
                  child: count == null
                      ? null
                      : Text(
                          count == 1 ? '1 NOTE' : '$count NOTES',
                          style: AppText.meta.copyWith(color: colors.inkMuted),
                        ),
                ),
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}
