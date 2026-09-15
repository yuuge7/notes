import 'package:notes/data/providers.dart';
import 'package:notes/domain/model/search.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'search_providers.g.dart';

@riverpod
Stream<SearchResults> searchResults(Ref ref, SearchQuery query) =>
    ref.watch(searchRepositoryProvider).watch(query);

@riverpod
Stream<SearchFacets> searchFacets(Ref ref) =>
    ref.watch(searchRepositoryProvider).watchFacets();

@riverpod
Stream<List<String>> recentSearches(Ref ref) =>
    ref.watch(searchRepositoryProvider).watchRecent();
