import 'dart:async';
import 'dart:io';

import 'package:animations/animations.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:notes/core/theme/app_colors.dart';
import 'package:notes/core/theme/tokens.dart';
import 'package:notes/core/theme/typography.dart';
import 'package:notes/core/ui/masonry.dart';
import 'package:notes/core/ui/shelf_scaffold.dart';
import 'package:notes/core/util/date_group.dart';
import 'package:notes/core/util/reorder.dart';
import 'package:notes/data/db/note_dao.dart';
import 'package:notes/data/media/photo_source.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/domain/model/note.dart';
import 'package:notes/features/editor/editor_outcome.dart';
import 'package:notes/features/editor/editor_screen.dart';
import 'package:notes/features/labels/label_providers.dart';
import 'package:notes/features/notes/notes_providers.dart';
import 'package:notes/features/notes/selection.dart';
import 'package:notes/features/notes/widgets/app_drawer.dart';
import 'package:notes/features/notes/widgets/compose_bar.dart';
import 'package:notes/features/notes/widgets/day_header.dart';
import 'package:notes/features/notes/widgets/note_tile.dart';
import 'package:notes/features/notes/widgets/notes_states.dart';
import 'package:notes/features/notes/widgets/selection_bar.dart';

/// The home grid: pinned notes first, then every other note under the day it
/// was captured. Given a label, the same grid holds only the notes wearing it.
class NotesScreen extends ConsumerWidget {
  const NotesScreen({this.labelId, super.key});

  /// The label to show notes for, or null for every note.
  final String? labelId;

  /// Two columns of cards, or one in list layout. The app is portrait-only on
  /// phones, so there is no wider breakpoint.
  static int columnsFor(NotesLayout layout) =>
      layout == NotesLayout.list ? 1 : 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labelId = this.labelId;
    final layout = ref.watch(notesLayoutModeProvider);
    final columns = columnsFor(layout);
    final startup = ref.watch(appStartupProvider);
    final AsyncValue<List<Note>>? notes;
    if (!startup.hasValue) {
      notes = null;
    } else if (labelId == null) {
      notes = ref.watch(shelfNotesProvider(Shelf.active));
    } else {
      notes = ref.watch(labelNotesProvider(labelId));
    }
    final noteList = notes?.value ?? const <Note>[];
    final selection = ref.watch(noteSelectionProvider(Shelf.active));
    final selecting = selection.isNotEmpty;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final colors = Theme.of(context).colors;

    final labels = labelId == null ? null : ref.watch(labelsProvider).value;
    final label = labels?.firstWhereOrNull((label) => label.id == labelId);
    // The label is gone, deleted from the labels page. Leave for the grid,
    // but only once this page is on top again: going now would also close
    // the labels page, and its undo with it.
    if (labels != null &&
        label == null &&
        (ModalRoute.of(context)?.isCurrent ?? true)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/');
      });
    }

    void retry() => labelId == null
        ? ref.invalidate(shelfNotesProvider(Shelf.active))
        : ref.invalidate(labelNotesProvider(labelId));

    final Widget content;
    if (startup.hasError) {
      content = NotesError(
        detail: '${startup.error}',
        onRetry: () => ref.invalidate(appStartupProvider),
      );
    } else if (notes == null || (notes.isLoading && !notes.hasValue)) {
      content = NotesSkeleton(columns: columns);
    } else if (notes.hasError) {
      content = NotesError(detail: '${notes.error}', onRetry: retry);
    } else if (noteList.isEmpty) {
      content = labelId == null
          ? const NotesEmpty()
          : LabelEmpty(name: label?.name ?? '');
    } else {
      content = _NotesGrid(
        notes: noteList,
        columns: columns,
        selection: selection,
        onToggleSelected: (id) => ref
            .read(noteSelectionProvider(Shelf.active).notifier)
            .toggle(id),
        onReorder: (noteId, prevKey, nextKey) {
          // A drag starts by selecting the note; landing it is a move, not a
          // selection, so the selection ends with the drag.
          ref.read(noteSelectionProvider(Shelf.active).notifier).clear();
          unawaited(
            ref
                .read(noteRepositoryProvider)
                .reorder(noteId, prevKey: prevKey, nextKey: nextKey),
          );
        },
        bottomPadding:
            Layout.composeBarHeight + Gap.lg * 2 + bottomInset + Gap.sm,
      );
    }

    return ShelfScaffold(
      // Back closes the drawer, then clears a selection. From the grid it
      // then leaves the app; from a label it returns to the grid.
      canPop: labelId == null && !selecting,
      onBlockedPop: () {
        if (selecting) {
          ref.read(noteSelectionProvider(Shelf.active).notifier).clear();
        } else if (labelId != null) {
          context.go('/');
        }
      },
      drawer: AppDrawer(
        currentPath: labelId == null ? '/' : '/label/$labelId',
      ),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                if (selecting)
                  SelectionBar(shelf: Shelf.active, notes: noteList)
                else
                  _Header(
                    title: labelId == null ? 'Notes' : label?.name ?? '',
                    count: notes?.value?.length,
                    layout: layout,
                    onToggleLayout: () =>
                        ref.read(notesLayoutModeProvider.notifier).toggle(),
                    onSearch: () => unawaited(context.push('/search')),
                  ),
                Expanded(
                  child: LayoutBuilder(
                    // Android can hand over a zero-width surface for the first
                    // frame, before the window has its size. Columns cannot be
                    // laid out in no space, so that frame is skipped rather
                    // than asserting on a negative width.
                    builder: (context, constraints) =>
                        constraints.maxWidth <
                            Layout.contentLeft +
                                Layout.contentRight +
                                Layout.cardGap * columns
                        ? const SizedBox.shrink()
                        : content,
                  ),
                ),
              ],
            ),
            // Capture steps aside while notes are selected, so a stray tap
            // cannot open a new note in the middle of a bulk edit — and the
            // fade that sits under it goes with it.
            if (!selecting) ...[
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: Layout.composeBarHeight + bottomInset + Gap.xl * 2,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          colors.ground.withValues(alpha: 0),
                          colors.ground,
                        ],
                        stops: const [0, 0.55],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: Layout.contentRight,
                right: Layout.contentRight,
                bottom: bottomInset + Gap.lg,
                child: _ComposeTile(labelId: labelId),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The compose bar, growing into a blank note or a blank list.
class _ComposeTile extends ConsumerStatefulWidget {
  const _ComposeTile({required this.labelId});

  /// The label a note started here wears from the start.
  final String? labelId;

  @override
  ConsumerState<_ComposeTile> createState() => _ComposeTileState();
}

class _ComposeTileState extends ConsumerState<_ComposeTile> {
  /// Which kind of note the next open starts. Set just before opening and
  /// read when the editor is built.
  bool _asList = false;

  /// Photos the next note starts with, taken just before opening.
  List<File> _photos = const [];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    final reduced = MediaQuery.disableAnimationsOf(context);

    return OpenContainer<EditorOutcome>(
      transitionDuration: Motion.of(context, Motion.container),
      transitionType: reduced
          ? ContainerTransitionType.fadeThrough
          : ContainerTransitionType.fade,
      closedElevation: 0,
      openElevation: 0,
      closedColor: colors.card,
      openColor: colors.card,
      middleColor: colors.card,
      closedShape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(Radii.bar)),
      ),
      tappable: false,
      onClosed: (outcome) => unawaited(
        applyEditorOutcome(context, ref.read(noteRepositoryProvider), outcome),
      ),
      closedBuilder: (context, open) {
        // A photo note opens only once there is a photo: closing the picker
        // or the camera leaves the grid as it was.
        Future<void> openWith(
          Future<List<File>> Function(PhotoSource source) take,
        ) async {
          final photos = await take(ref.read(photoSourceProvider));
          if (photos.isEmpty || !mounted) return;
          _asList = false;
          _photos = photos;
          open();
        }

        return ComposeBar(
          onTap: () {
            _asList = false;
            _photos = const [];
            open();
          },
          onNewList: () {
            _asList = true;
            _photos = const [];
            open();
          },
          onAddImage: () =>
              unawaited(openWith((source) => source.pickPhotos())),
          onTakePhoto: () => unawaited(
            openWith((source) async => [?await source.takePhoto()]),
          ),
        );
      },
      openBuilder: (context, _) => EditorScreen(
        startAsChecklist: _asList,
        labelId: widget.labelId,
        initialPhotos: _photos,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.count,
    required this.layout,
    required this.onToggleLayout,
    required this.onSearch,
  });

  final String title;
  final int? count;
  final NotesLayout layout;
  final VoidCallback onToggleLayout;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    final isGrid = layout == NotesLayout.grid;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.xs, Gap.lg, Gap.xs, Gap.sm),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.display.copyWith(color: colors.ink),
                  ),
                ),
                const SizedBox(height: Gap.xs),
                // Reserve the line so the header does not jump when the count
                // arrives.
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
          IconButton(
            onPressed: onSearch,
            tooltip: 'Search',
            icon: Icon(Icons.search, color: colors.inkMuted),
          ),
          IconButton(
            onPressed: onToggleLayout,
            tooltip: isGrid ? 'Show as list' : 'Show as grid',
            icon: Icon(
              isGrid ? Icons.view_agenda_outlined : Icons.grid_view_outlined,
              color: colors.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// A headed run of notes on the grid: the pinned notes, or one day's.
///
/// `start` is where the section begins in `runKeys`, the sort keys of the
/// run it belongs to, so a move inside the section finds its neighbours.
typedef _Section = ({
  String id,
  String label,
  List<Note> notes,
  int start,
  List<String> runKeys,
});

class _NotesGrid extends StatefulWidget {
  const _NotesGrid({
    required this.notes,
    required this.columns,
    required this.selection,
    required this.onToggleSelected,
    required this.onReorder,
    required this.bottomPadding,
  });

  final List<Note> notes;
  final int columns;
  final Set<String> selection;
  final ValueChanged<String> onToggleSelected;

  /// Places a note between the notes with these keys; null is an open end.
  final void Function(String noteId, String? prevKey, String? nextKey)
  onReorder;
  final double bottomPadding;

  @override
  State<_NotesGrid> createState() => _NotesGridState();
}

class _NotesGridState extends State<_NotesGrid> {
  /// How close to the top or bottom edge a held note starts the grid
  /// scrolling.
  static const _edgeZone = 72.0;

  /// Fastest scroll, in logical pixels per tick, reached at the very edge.
  static const _maxStep = 18.0;
  static const _tick = Duration(milliseconds: 16);

  final _scroll = ScrollController();
  Timer? _autoScroll;
  bool _dragging = false;
  double _step = 0;

  @override
  void dispose() {
    _autoScroll?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _dragStarted() => _dragging = true;

  void _dragStopped() {
    _dragging = false;
    _setStep(0);
  }

  /// Scrolls while a dragged note is held near an edge, faster the deeper it
  /// sits in the edge zone.
  ///
  /// This follows the pointer rather than the dragged card: once the card
  /// scrolls out of view it is disposed and stops reporting, but the pointer
  /// keeps arriving here until the finger lifts.
  void _onPointerMove(PointerMoveEvent event) {
    if (!_dragging) return;
    final box = context.findRenderObject()! as RenderBox;
    final y = box.globalToLocal(event.position).dy;
    final height = box.size.height;

    var step = 0.0;
    if (y < _edgeZone) {
      step = -_maxStep * (1 - y.clamp(0, _edgeZone) / _edgeZone);
    } else if (y > height - _edgeZone) {
      step = _maxStep * (1 - (height - y).clamp(0, _edgeZone) / _edgeZone);
    }
    _setStep(step);
  }

  void _setStep(double step) {
    _step = step;
    if (step == 0) {
      _autoScroll?.cancel();
      _autoScroll = null;
      return;
    }
    _autoScroll ??= Timer.periodic(_tick, (_) {
      if (!_scroll.hasClients) return;
      final position = _scroll.position;
      final target = (position.pixels + _step).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (target != position.pixels) _scroll.jumpTo(target);
    });
  }

  @override
  Widget build(BuildContext context) {
    final notes = widget.notes;
    final pinned = notes.where((note) => note.pinned).toList();
    final others = notes.where((note) => !note.pinned).toList();
    final days = groupByDay(others, (note) => note.createdAt);

    // Pinned and unpinned notes sort as two independent runs, so each
    // section's neighbours come from its own run. A day section is a slice
    // of the unpinned run starting at [start].
    final pinnedKeys = [for (final note in pinned) note.sortKey];
    final otherKeys = [for (final note in others) note.sortKey];

    final sections = <_Section>[
      if (pinned.isNotEmpty)
        (
          id: 'pinned',
          label: 'PINNED',
          notes: pinned,
          start: 0,
          runKeys: pinnedKeys,
        ),
    ];
    var start = 0;
    for (final (group, dayNotes) in days) {
      sections.add((
        id: 'day-${group.day.millisecondsSinceEpoch}',
        label: group.label,
        notes: dayNotes,
        start: start,
        runKeys: otherKeys,
      ));
      start += dayNotes.length;
    }

    return Listener(
      onPointerMove: _onPointerMove,
      onPointerUp: (_) => _dragStopped(),
      onPointerCancel: (_) => _dragStopped(),
      child: Stack(
        children: [
          const Positioned.fill(child: TimeGutter()),
          CustomScrollView(
            controller: _scroll,
            slivers: [
              // One lazily built item per section, each laying out its own
              // columns. A masonry sliver per section stopped the grid short
              // of its end; see MasonryColumns.
              SliverList.builder(
                itemCount: sections.length,
                // Keeps a section's cards, and any editor open from one, when
                // a new day arrives above it.
                findChildIndexCallback: (key) {
                  final index = sections.indexWhere(
                    (section) => ValueKey(section.id) == key,
                  );
                  return index < 0 ? null : index;
                },
                itemBuilder: (context, index) => _section(sections[index]),
              ),
              SliverToBoxAdapter(
                child: SizedBox(height: widget.bottomPadding),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _section(_Section section) {
    final sectionNotes = section.notes;

    void move(String noteId, int toIndex) {
      final from = sectionNotes.indexWhere((note) => note.id == noteId);
      if (from < 0) return;
      final bounds = neighboursForMove(
        section.runKeys,
        from: section.start + from,
        to: section.start + toIndex,
      );
      if (bounds == null) return;
      widget.onReorder(noteId, bounds.prev, bounds.next);
    }

    return Column(
      key: ValueKey(section.id),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DayHeader(label: section.label),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Layout.contentLeft,
            Gap.xs,
            Layout.contentRight,
            Gap.lg,
          ),
          child: MasonryColumns(
            columns: widget.columns,
            spacing: Layout.cardGap,
            children: [
              for (final (index, note) in sectionNotes.indexed)
                RepaintBoundary(
                  key: ValueKey(note.id),
                  child: NoteTile(
                    key: ValueKey(note.id),
                    note: note,
                    selecting: widget.selection.isNotEmpty,
                    selected: widget.selection.contains(note.id),
                    onToggleSelected: () => widget.onToggleSelected(note.id),
                    reorder: TileReorder(
                      section: section.id,
                      index: index,
                      length: sectionNotes.length,
                      onMove: move,
                      onDragStart: _dragStarted,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
