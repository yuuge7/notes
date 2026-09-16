import 'package:drift/drift.dart';
import 'package:notes/core/util/search_text.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/db/search_index.dart';
import 'package:notes/data/db/tables.dart';
import 'package:notes/data/mapper/note_mapper.dart';
import 'package:notes/domain/model/note_type.dart';
import 'package:notes/domain/model/pigment.dart';
import 'package:notes/domain/model/search.dart';

part 'search_dao.g.dart';

/// Full-text search over notes outside the trash, the filters that can
/// narrow it, and the last few searches.
@DriftAccessor(tables: [Notes, Labels, NoteLabels, Attachments, RecentSearches])
class SearchDao extends DatabaseAccessor<AppDatabase> with _$SearchDaoMixin {
  SearchDao(super.attachedDatabase);

  /// Most notes one search loads. Plenty to scroll through; past it another
  /// word narrows faster than scrolling, and the count says there is more.
  static const limit = 150;

  /// Searches offered again when the field is empty.
  static const recentCount = 3;

  /// Indexes every note from scratch, for when search seems to miss one.
  Future<void> rebuildIndex() =>
      transaction(() => SearchIndex.rebuild(customStatement));

  /// Emits results now, and again whenever a note changes.
  Stream<SearchResults> watch(SearchQuery query) =>
      attachedDatabase.noteDao.reloadOnChange(() => search(query));

  Future<SearchResults> search(SearchQuery query, {int limit = limit}) async {
    if (query.isEmpty) return const SearchResults();
    final terms = query.terms;
    final where = _where(query, terms);

    final String from;
    final String order;
    if (terms.isEmpty) {
      // Filters alone: the order of the grid.
      from = 'notes n';
      order = 'n.archived, n.pinned DESC, n.sort_key';
    } else {
      // A word in the title outweighs the same word in a long body; a label
      // is nearly as telling as a title.
      from = 'notes_fts JOIN notes n ON n.rowid = notes_fts.rowid';
      order = 'n.archived, bm25(notes_fts, 10.0, 2.0, 2.0, 6.0), n.sort_key';
    }

    final rows = await customSelect(
      'SELECT n.* FROM $from WHERE ${where.sql} ORDER BY $order LIMIT ?',
      variables: [...where.variables, Variable.withInt(limit)],
    ).get();

    final total = rows.length < limit
        ? rows.length
        : (await customSelect(
            'SELECT count(*) AS total FROM $from WHERE ${where.sql}',
            variables: where.variables,
          ).getSingle()).read<int>('total');

    return SearchResults(
      notes: await attachedDatabase.noteDao.hydrate([
        for (final row in rows) notes.map(row.data),
      ]),
      total: total,
      terms: terms,
    );
  }

  ({String sql, List<Variable<Object>> variables}) _where(
    SearchQuery query,
    List<String> terms,
  ) {
    final clauses = ['n.deleted = 0'];
    final variables = <Variable<Object>>[];

    if (terms.isNotEmpty) {
      clauses.add('notes_fts MATCH ?');
      variables.add(Variable.withString(SearchText.matchQuery(terms)));
    }
    switch (query.kind) {
      case null:
        break;
      case NoteKind.list:
        clauses.add('n.type = ?');
        variables.add(Variable.withString(NoteType.checklist.name));
      case NoteKind.reminder:
        clauses.add('n.reminder_at_ms IS NOT NULL');
      case NoteKind.image:
        clauses.add(
          'EXISTS (SELECT 1 FROM attachments a '
          'WHERE a.note_id = n.id AND a.deleted = 0)',
        );
    }
    if (query.pigment case final pigment?) {
      clauses.add('n.pigment = ?');
      variables.add(Variable.withString(pigment.name));
    }
    if (query.labelId case final labelId?) {
      clauses.add(
        'EXISTS (SELECT 1 FROM note_labels nl JOIN labels l '
        'ON l.id = nl.label_id WHERE nl.note_id = n.id AND nl.label_id = ? '
        'AND nl.deleted = 0 AND l.deleted = 0)',
      );
      variables.add(Variable.withString(labelId));
    }
    return (sql: clauses.join(' AND '), variables: variables);
  }

  Stream<SearchFacets> watchFacets() =>
      attachedDatabase.noteDao.reloadOnChange(facets);

  Future<SearchFacets> facets() async {
    final kinds = await customSelect(
      'SELECT '
      'EXISTS (SELECT 1 FROM notes WHERE deleted = 0 AND type = ?) AS lists, '
      'EXISTS (SELECT 1 FROM notes '
      'WHERE deleted = 0 AND reminder_at_ms IS NOT NULL) AS reminders, '
      'EXISTS (SELECT 1 FROM attachments a JOIN notes n ON n.id = a.note_id '
      'WHERE a.deleted = 0 AND n.deleted = 0) AS images',
      variables: [Variable.withString(NoteType.checklist.name)],
    ).getSingle();

    final pigmentRows = await customSelect(
      'SELECT DISTINCT pigment FROM notes WHERE deleted = 0',
    ).get();
    final used = {for (final row in pigmentRows) row.read<String>('pigment')};

    final labelRows = await customSelect(
      'SELECT DISTINCT l.* FROM labels l '
      'JOIN note_labels nl ON nl.label_id = l.id AND nl.deleted = 0 '
      'JOIN notes n ON n.id = nl.note_id AND n.deleted = 0 '
      'WHERE l.deleted = 0 ORDER BY l.sort_key',
    ).get();

    return SearchFacets(
      kinds: [
        if (kinds.read<bool>('lists')) NoteKind.list,
        if (kinds.read<bool>('reminders')) NoteKind.reminder,
        if (kinds.read<bool>('images')) NoteKind.image,
      ],
      pigments: [
        for (final pigment in Pigment.values)
          if (used.contains(pigment.name)) pigment,
      ],
      labels: [for (final row in labelRows) labels.map(row.data).toDomain()],
    );
  }

  Stream<List<String>> watchRecent() =>
      (select(recentSearches)
            ..orderBy([(t) => OrderingTerm.desc(t.usedAtMs)])
            ..limit(recentCount))
          .map((row) => row.query)
          .watch();

  /// Records [raw] as the latest search, keeping only the last few.
  Future<void> remember(String raw) async {
    final query = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (SearchText.terms(query).isEmpty) return;

    await transaction(() async {
      // Strictly later than the last entry, so two searches in the same
      // millisecond still keep their order.
      final latest = recentSearches.usedAtMs.max();
      final previous = await (selectOnly(
        recentSearches,
      )..addColumns([latest])).map((row) => row.read(latest)).getSingle();
      final now = DateTime.now().millisecondsSinceEpoch;
      final usedAt = previous != null && previous >= now ? previous + 1 : now;

      await into(recentSearches).insertOnConflictUpdate(
        RecentSearchesCompanion.insert(
          folded: query.toLowerCase(),
          query: query,
          usedAtMs: usedAt,
        ),
      );
      await customUpdate(
        'DELETE FROM recent_searches WHERE folded NOT IN '
        '(SELECT folded FROM recent_searches '
        'ORDER BY used_at_ms DESC LIMIT $recentCount)',
        updates: {recentSearches},
        updateKind: UpdateKind.delete,
      );
    });
  }

  Future<void> clearRecent() => delete(recentSearches).go();
}
