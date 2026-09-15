import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:notes/core/theme/app_colors.dart';
import 'package:notes/core/theme/tokens.dart';
import 'package:notes/core/theme/typography.dart';
import 'package:notes/core/ui/masonry.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/domain/model/note.dart';
import 'package:notes/domain/model/pigment.dart';
import 'package:notes/domain/model/search.dart';
import 'package:notes/features/notes/notes_providers.dart';
import 'package:notes/features/notes/notes_screen.dart';
import 'package:notes/features/notes/widgets/note_tile.dart';
import 'package:notes/features/notes/widgets/notes_states.dart';
import 'package:notes/features/search/search_providers.dart';

/// Search across every note outside the trash: words as they are typed,
/// narrowed by kind of note, colour, or label.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  /// Long enough that a word typed at speed runs one query, short enough that
  /// results still follow the keys.
  static const _debounce = Duration(milliseconds: 150);

  final _field = TextEditingController();
  final _focus = FocusNode();
  Timer? _typing;
  SearchQuery _query = const SearchQuery();

  /// The results last shown. They stay on the page while the next query
  /// runs, so it does not blink empty between keystrokes.
  SearchResults? _lastResults;

  @override
  void dispose() {
    _typing?.cancel();
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onTyped(String text) {
    // Rebuild now for the clear button; search after the pause.
    setState(() {});
    _typing?.cancel();
    _typing = Timer(_debounce, () {
      if (mounted) setState(() => _query = _query.copyWith(text: text));
    });
  }

  void _searchNow(String text) {
    _typing?.cancel();
    if (_field.text != text) {
      _field.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    setState(() => _query = _query.copyWith(text: text));
  }

  /// Keeps the search for next time. Runs when the search is acted on —
  /// a result opened, or the keyboard's search key — so half-typed words are
  /// never remembered.
  void _remember() =>
      unawaited(ref.read(searchRepositoryProvider).remember(_field.text));

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    final columns = NotesScreen.columnsFor(ref.watch(notesLayoutModeProvider));
    final facets =
        ref.watch(searchFacetsProvider).value ?? const SearchFacets();

    final Widget body;
    if (_query.isEmpty) {
      _lastResults = null;
      body = _Start(onUse: _searchNow);
    } else {
      final results = ref.watch(searchResultsProvider(_query));
      final shown = results.value ?? _lastResults;
      _lastResults = shown;
      if (results.hasError) {
        body = NotesError(
          detail: '${results.error}',
          onRetry: () => ref.invalidate(searchResultsProvider(_query)),
        );
      } else if (shown == null) {
        body = const SizedBox.shrink();
      } else if (shown.notes.isEmpty) {
        body = _NoMatches(
          query: _query,
          onClearFilters: () =>
              setState(() => _query = SearchQuery(text: _query.text)),
        );
      } else {
        body = _Results(results: shown, columns: columns, onOpen: _remember);
      }
    }

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
                      focusNode: _focus,
                      autofocus: true,
                      onChanged: _onTyped,
                      onSubmitted: (text) {
                        _searchNow(text);
                        _remember();
                      },
                      textInputAction: TextInputAction.search,
                      style: AppText.uiLarge.copyWith(color: colors.ink),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: Gap.md,
                        ),
                        hintText: 'Search notes',
                        hintStyle: AppText.uiLarge.copyWith(
                          color: colors.inkMuted,
                        ),
                      ),
                    ),
                  ),
                  if (_field.text.isNotEmpty)
                    IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchNow('');
                        _focus.requestFocus();
                      },
                      icon: Icon(Icons.close, color: colors.inkMuted),
                    ),
                ],
              ),
            ),
            _FilterRow(
              query: _query,
              facets: facets,
              onChanged: (query) => setState(() => _query = query),
            ),
            const Divider(),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// Type, colour, and label, each offered only when some note could match it.
class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.query,
    required this.facets,
    required this.onChanged,
  });

  final SearchQuery query;
  final SearchFacets facets;
  final ValueChanged<SearchQuery> onChanged;

  @override
  Widget build(BuildContext context) {
    final showKind = facets.kinds.isNotEmpty || query.kind != null;
    // One colour in use is no choice at all.
    final showColour = facets.pigments.length > 1 || query.pigment != null;
    final showLabel = facets.labels.isNotEmpty || query.labelId != null;
    if (!showKind && !showColour && !showLabel) {
      return const SizedBox(height: Gap.sm);
    }

    final pigment = query.pigment;
    final label = facets.labels.firstWhereOrNull((l) => l.id == query.labelId);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: Gap.md),
      child: Row(
        children: [
          if (showKind)
            _FilterMenu<NoteKind>(
              name: 'Type',
              anyLabel: 'Any type',
              selected: query.kind,
              selectedLabel: query.kind?.label,
              options: [
                for (final kind in facets.kinds)
                  (kind, kind.label, Icon(_kindIcon(kind), size: 18)),
              ],
              onSelected: (kind) => onChanged(query.copyWith(kind: kind)),
            ),
          if (showColour)
            _FilterMenu<Pigment>(
              name: 'Colour',
              anyLabel: 'Any colour',
              selected: pigment,
              selectedLabel: pigment == null ? null : _pigmentName(pigment),
              leading: pigment == null ? null : _Swatch(pigment: pigment),
              options: [
                for (final option in facets.pigments)
                  (option, _pigmentName(option), _Swatch(pigment: option)),
              ],
              onSelected: (value) => onChanged(query.copyWith(pigment: value)),
            ),
          if (showLabel)
            _FilterMenu<String>(
              name: 'Label',
              anyLabel: 'Any label',
              selected: query.labelId,
              selectedLabel: query.labelId == null
                  ? null
                  : label?.name ?? 'Label',
              options: [
                for (final option in facets.labels)
                  (
                    option.id,
                    option.name,
                    const Icon(Icons.label_outline, size: 18),
                  ),
              ],
              onSelected: (id) => onChanged(query.copyWith(labelId: id)),
            ),
        ],
      ),
    );
  }

  static IconData _kindIcon(NoteKind kind) => switch (kind) {
    NoteKind.list => Icons.check_box_outlined,
    NoteKind.reminder => Icons.alarm,
    NoteKind.image => Icons.image_outlined,
  };

  static String _pigmentName(Pigment pigment) =>
      pigment.isNone ? 'No colour' : pigment.label;
}

/// A chip that opens a menu of choices, and shows the one picked.
class _FilterMenu<T> extends StatelessWidget {
  const _FilterMenu({
    required this.name,
    required this.anyLabel,
    required this.selected,
    required this.selectedLabel,
    required this.options,
    required this.onSelected,
    this.leading,
  });

  final String name;

  /// The menu entry that clears the filter, such as "Any colour".
  final String anyLabel;
  final T? selected;
  final String? selectedLabel;
  final List<(T, String, Widget)> options;
  final ValueChanged<T?> onSelected;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    final active = selected != null;

    return MenuAnchor(
      alignmentOffset: const Offset(Gap.xs, 0),
      menuChildren: [
        if (active)
          MenuItemButton(
            onPressed: () => onSelected(null),
            leadingIcon: Icon(Icons.close, size: 18, color: colors.inkMuted),
            child: Text(anyLabel),
          ),
        for (final (value, label, icon) in options)
          MenuItemButton(
            onPressed: () => onSelected(value),
            leadingIcon: icon,
            trailingIcon: value == selected
                ? Icon(Icons.check, size: 18, color: colors.accent)
                : null,
            child: Text(label),
          ),
      ],
      builder: (context, controller, _) {
        void toggle() => controller.isOpen ? controller.close() : controller.open();
        return Semantics(
          button: true,
          label: active ? '$name: $selectedLabel' : '$name filter',
          excludeSemantics: true,
          onTap: toggle,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: toggle,
            // The chip is drawn at 40 but answers across 48, the smallest
            // comfortable target.
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.xs,
                vertical: Gap.xs,
              ),
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: active ? colors.accentWash : null,
                  shape: StadiumBorder(
                    side: BorderSide(
                      color: active ? colors.accent : colors.hairline,
                    ),
                  ),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 40),
                  child: Padding(
                    padding: const EdgeInsets.only(left: Gap.md, right: Gap.sm),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (leading != null) ...[
                          leading!,
                          const SizedBox(width: Gap.sm),
                        ],
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 180),
                          child: Text(
                            selectedLabel ?? name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: (active ? AppText.uiStrong : AppText.ui)
                                .copyWith(
                                  color: active ? colors.ink : colors.inkMuted,
                                ),
                          ),
                        ),
                        const SizedBox(width: Gap.xs),
                        Icon(
                          Icons.expand_more,
                          size: 18,
                          color: colors.inkMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.pigment});

  final Pigment pigment;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: pigment.isNone ? colors.card : colors.swatch(pigment).spine,
        border: pigment.isNone ? Border.all(color: colors.inkMuted) : null,
      ),
    );
  }
}

/// Before anything is typed: the last few searches, or what search covers.
class _Start extends ConsumerWidget {
  const _Start({required this.onUse});

  final ValueChanged<String> onUse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colors;
    final recent = ref.watch(recentSearchesProvider).value ?? const <String>[];

    if (recent.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(Gap.xl),
        children: [
          Text(
            'SEARCH',
            style: AppText.metaStrong.copyWith(color: colors.inkMuted),
          ),
          const SizedBox(height: Gap.md),
          Text(
            'Find anything you wrote',
            style: AppText.display.copyWith(color: colors.ink),
          ),
          const SizedBox(height: Gap.sm),
          Text(
            'Titles, text, list items, and labels, archived notes included. '
            'A word matches from its first letters.',
            style: AppText.noteBody.copyWith(color: colors.inkMuted),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.only(top: Gap.sm),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Layout.contentRight,
            0,
            Gap.xs,
            0,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'RECENT',
                  style: AppText.metaStrong.copyWith(color: colors.inkMuted),
                ),
              ),
              TextButton(
                onPressed: () => unawaited(
                  ref.read(searchRepositoryProvider).clearRecent(),
                ),
                child: const Text('Clear'),
              ),
            ],
          ),
        ),
        for (final query in recent)
          Semantics(
            button: true,
            label: 'Search again for $query',
            excludeSemantics: true,
            onTap: () => onUse(query),
            child: InkWell(
              onTap: () => onUse(query),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 52),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Layout.contentRight,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.history, size: 20, color: colors.inkMuted),
                      const SizedBox(width: Gap.lg),
                      Expanded(
                        child: Text(
                          query,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.uiLarge.copyWith(color: colors.ink),
                        ),
                      ),
                      Icon(Icons.north_west, size: 18, color: colors.inkMuted),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.query, required this.onClearFilters});

  final SearchQuery query;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    final text = query.text.trim();

    return ListView(
      padding: const EdgeInsets.all(Gap.xl),
      children: [
        Text(
          'NO MATCHES',
          style: AppText.metaStrong.copyWith(color: colors.inkMuted),
        ),
        const SizedBox(height: Gap.md),
        Text(
          query.terms.isEmpty ? 'No notes like that' : 'Nothing matches “$text”',
          style: AppText.display.copyWith(color: colors.ink),
        ),
        const SizedBox(height: Gap.sm),
        Text(
          query.hasFilters
              ? 'Try fewer letters, or clear the filters.'
              : 'Try fewer letters or another word. '
                    'Notes in the trash are not searched.',
          style: AppText.noteBody.copyWith(color: colors.inkMuted),
        ),
        if (query.hasFilters) ...[
          const SizedBox(height: Gap.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onClearFilters,
              child: const Text('Clear filters'),
            ),
          ),
        ],
      ],
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.results,
    required this.columns,
    required this.onOpen,
  });

  final SearchResults results;
  final int columns;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    final notes = results.notes;
    final active = [for (final note in notes) if (!note.archived) note];
    final archived = [for (final note in notes) if (note.archived) note];
    final total = results.total;

    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Layout.contentRight,
              Gap.md,
              Layout.contentRight,
              Gap.sm,
            ),
            child: Semantics(
              liveRegion: true,
              child: Text(
                total == 1 ? '1 NOTE' : '$total NOTES',
                style: AppText.meta.copyWith(color: colors.inkMuted),
              ),
            ),
          ),
        ),
        if (active.isNotEmpty) _grid(active),
        if (archived.isNotEmpty) ...[
          const SliverToBoxAdapter(child: _SectionHeader(label: 'ARCHIVE')),
          _grid(archived),
        ],
        if (total > notes.length)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Layout.contentRight,
                vertical: Gap.sm,
              ),
              child: Text(
                'SHOWING ${notes.length} OF $total · ADD A WORD TO NARROW',
                style: AppText.meta.copyWith(color: colors.inkMuted),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: Gap.xxl + MediaQuery.paddingOf(context).bottom,
          ),
        ),
      ],
    );
  }

  /// One box of cards per group. Stacked masonry slivers stopped scrolling
  /// short of the end (see MasonryColumns), and a search loads a bounded
  /// number of notes, so a group's cards are built together.
  Widget _grid(List<Note> notes) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Layout.contentRight,
          0,
          Layout.contentRight,
          Gap.lg,
        ),
        child: MasonryColumns(
          columns: columns,
          spacing: Layout.cardGap,
          children: [
            for (final note in notes)
              RepaintBoundary(
                key: ValueKey(note.id),
                child: NoteTile(
                  key: ValueKey(note.id),
                  note: note,
                  selecting: false,
                  selected: false,
                  onToggleSelected: null,
                  highlight: results.terms,
                  onOpen: onOpen,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Layout.contentRight,
          Gap.sm,
          Layout.contentRight,
          Gap.md,
        ),
        child: Row(
          children: [
            Text(
              label,
              style: AppText.metaStrong.copyWith(color: colors.inkMuted),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Container(height: Stroke.hairline, color: colors.hairline),
            ),
          ],
        ),
      ),
    );
  }
}
