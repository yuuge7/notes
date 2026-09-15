import 'package:notes/data/db/search_dao.dart';
import 'package:notes/domain/model/search.dart';

/// Search, its filters, and the searches worth offering again.
class SearchRepository {
  SearchRepository(this._dao);

  final SearchDao _dao;

  Stream<SearchResults> watch(SearchQuery query) => _dao.watch(query);

  Future<SearchResults> search(SearchQuery query) => _dao.search(query);

  Stream<SearchFacets> watchFacets() => _dao.watchFacets();

  Stream<List<String>> watchRecent() => _dao.watchRecent();

  Future<void> remember(String query) => _dao.remember(query);

  Future<void> clearRecent() => _dao.clearRecent();
}
