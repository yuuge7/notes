import 'dart:async';

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:notes/core/theme/app_colors.dart';
import 'package:notes/core/theme/tokens.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/domain/model/note.dart';
import 'package:notes/domain/model/settings.dart';
import 'package:notes/features/editor/editor_outcome.dart';
import 'package:notes/features/editor/editor_screen.dart';
import 'package:notes/features/notes/widgets/note_card.dart';

/// Where a tile sits for reordering, and what happens when a note moves.
@immutable
class TileReorder {
  const TileReorder({
    required this.section,
    required this.index,
    required this.length,
    required this.onMove,
    this.onDragStart,
  });

  /// Notes move only within their own section. A note dropped under another
  /// day would jump back under the day it was captured on the next rebuild.
  final String section;

  /// This tile's position within [section].
  final int index;

  /// How many notes [section] holds.
  final int length;

  /// Moves the note with the given id to a new position within [section].
  final void Function(String noteId, int toIndex) onMove;

  /// Called when a drag of this tile begins, so the grid can scroll while the
  /// note is held near an edge.
  final VoidCallback? onDragStart;
}

@immutable
class _Dragged {
  const _Dragged({required this.noteId, required this.section});

  final String noteId;
  final String section;
}

/// A card that grows into its editor and, where [reorder] is given, can be
/// dragged to a new place in its section.
///
/// Card and editor share one surface colour, so the container transform reads
/// as the same sheet of paper opening out rather than a new page arriving.
class NoteTile extends ConsumerWidget {
  const NoteTile({
    required this.note,
    required this.selecting,
    required this.selected,
    required this.onToggleSelected,
    this.reorder,
    this.readOnly = false,
    this.highlight = const [],
    this.onOpen,
    super.key,
  });

  final Note note;

  /// Search words to mark on the card.
  final List<String> highlight;

  /// Called as the card opens into its editor, such as to remember the
  /// search that found it.
  final VoidCallback? onOpen;

  /// While any note is selected, a tap selects instead of opening.
  final bool selecting;
  final bool selected;

  /// Null where notes cannot be selected, such as the trash.
  final VoidCallback? onToggleSelected;

  /// Null where notes keep a fixed order.
  final TileReorder? reorder;
  final bool readOnly;

  static const CustomSemanticsAction _moveEarlier = CustomSemanticsAction(label: 'Move earlier');
  static const CustomSemanticsAction _moveLater = CustomSemanticsAction(label: 'Move later');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final move = reorder;
    if (move == null) return _container(context, ref, dropTarget: false);

    return LayoutBuilder(
      builder: (context, constraints) => DragTarget<_Dragged>(
        onWillAcceptWithDetails: (details) =>
            details.data.section == move.section &&
            details.data.noteId != note.id,
        onAcceptWithDetails: (details) =>
            move.onMove(details.data.noteId, move.index),
        builder: (context, candidates, _) {
          final card = _container(
            context,
            ref,
            dropTarget: candidates.isNotEmpty,
          );
          return LongPressDraggable<_Dragged>(
            data: _Dragged(noteId: note.id, section: move.section),
            // Long-press selects, as it does everywhere else; moving before
            // letting go turns the same press into a drag.
            onDragStarted: () {
              if (!selected) onToggleSelected?.call();
              move.onDragStart?.call();
            },
            feedback: _DragFeedback(note: note, width: constraints.maxWidth),
            childWhenDragging: Opacity(opacity: 0.35, child: card),
            child: card,
          );
        },
      ),
    );
  }

  Widget _container(
    BuildContext context,
    WidgetRef ref, {
    required bool dropTarget,
  }) {
    final surface = Theme.of(context).colors.surfaceFor(note.pigment);
    final checkedInPlace = ref.watch(
      appSettingsProvider.select(
        (settings) => settings.value?.checkedItems == CheckedItems.inPlace,
      ),
    );
    final reduced = MediaQuery.disableAnimationsOf(context);
    final move = reorder;

    return OpenContainer<EditorOutcome>(
      transitionDuration: Motion.of(context, Motion.container),
      transitionType: reduced
          ? ContainerTransitionType.fadeThrough
          : ContainerTransitionType.fade,
      closedElevation: 0,
      openElevation: 0,
      closedColor: surface,
      openColor: surface,
      middleColor: surface,
      closedShape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(Radii.card)),
      ),
      tappable: false,
      onClosed: (outcome) => unawaited(
        applyEditorOutcome(context, ref.read(noteRepositoryProvider), outcome),
      ),
      closedBuilder: (context, open) => NoteCard(
        note: note,
        selected: selected,
        dropTarget: dropTarget,
        highlight: highlight,
        checkedInPlace: checkedInPlace,
        onTap: selecting && onToggleSelected != null
            ? onToggleSelected!
            : () {
                onOpen?.call();
                open();
              },
        // With reordering on, the draggable owns the long-press gesture.
        onLongPress: move == null ? onToggleSelected : null,
        semanticLongPress: onToggleSelected,
        // Moving without a drag, for people who cannot drag.
        semanticActions: move == null
            ? null
            : {
                if (move.index > 0)
                  _moveEarlier: () => move.onMove(note.id, move.index - 1),
                if (move.index < move.length - 1)
                  _moveLater: () => move.onMove(note.id, move.index + 1),
              },
      ),
      openBuilder: (context, _) =>
          EditorScreen(noteId: note.id, readOnly: readOnly),
    );
  }
}

/// The card under the finger while dragging: lifted a touch by scale rather
/// than a shadow, in keeping with an interface drawn in hairlines.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.note, required this.width});

  final Note note;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: width,
        child: Transform.scale(
          scale: 1.03,
          child: NoteCard(note: note, selected: true, onTap: () {}),
        ),
      ),
    );
  }
}
