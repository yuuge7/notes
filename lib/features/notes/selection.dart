import 'package:notes/data/db/note_dao.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'selection.g.dart';

/// Notes picked by long-press on one shelf. Empty means selection mode is off.
///
/// Kept per shelf so selecting in the archive never carries over to the grid.
@riverpod
class NoteSelection extends _$NoteSelection {
  @override
  Set<String> build(Shelf shelf) => const {};

  void toggle(String id) {
    state = state.contains(id) ? (Set.of(state)..remove(id)) : {...state, id};
  }

  void clear() => state = const {};
}
