import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:notes/core/util/search_text.dart';
import 'package:notes/domain/model/label.dart';
import 'package:notes/domain/model/note.dart';
import 'package:notes/domain/model/pigment.dart';

part 'search.freezed.dart';

/// A kind of note that search can narrow to.
enum NoteKind {
  list('Lists'),
  reminder('Reminders'),
  image('Images');

  NoteKind(this.label);

  final String label;
}

/// What to look for: typed words, and any filters picked beside them.
@freezed
abstract class SearchQuery with _$SearchQuery {
  const factory SearchQuery({
    @Default('') String text,
    NoteKind? kind,
    Pigment? pigment,
    String? labelId,
  }) = _SearchQuery;

  const SearchQuery._();

  List<String> get terms => SearchText.terms(text);

  bool get hasFilters => kind != null || pigment != null || labelId != null;

  /// Nothing typed and nothing picked, so nothing to search for.
  bool get isEmpty => terms.isEmpty && !hasFilters;
}

/// What a search found.
@freezed
abstract class SearchResults with _$SearchResults {
  const factory SearchResults({
    /// Notes outside the archive first, then archived ones, up to the search
    /// limit.
    @Default(<Note>[]) List<Note> notes,

    /// Every match, counting those past the limit.
    @Default(0) int total,

    /// The words searched for, to highlight in the results.
    @Default(<String>[]) List<String> terms,
  }) = _SearchResults;
}

/// The filters worth offering: only kinds, colours, and labels some note
/// outside the trash has, so no filter leads to an empty page.
@freezed
abstract class SearchFacets with _$SearchFacets {
  const factory SearchFacets({
    @Default(<NoteKind>[]) List<NoteKind> kinds,
    @Default(<Pigment>[]) List<Pigment> pigments,
    @Default(<Label>[]) List<Label> labels,
  }) = _SearchFacets;
}
