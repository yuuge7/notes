import 'package:notes/data/db/note_dao.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/data/seed.dart';
import 'package:notes/domain/model/note.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'notes_providers.g.dart';

/// Two ways to read the grid: masonry cards, or one dense column.
enum NotesLayout { grid, list }

/// Work that has to finish before the first read: trash past the stay chosen
/// in settings is purged and, on a fresh install, the starter notes are
/// written.
@Riverpod(keepAlive: true)
Future<void> appStartup(Ref ref) async {
  final repository = ref.watch(noteRepositoryProvider);
  final settings = await ref.watch(settingsRepositoryProvider).load();
  await repository.purgeExpiredTrash(settings.trashRetention.duration);
  await seedIfEmpty(ref.watch(noteDaoProvider));
}

@riverpod
Stream<List<Note>> shelfNotes(Ref ref, Shelf shelf) =>
    ref.watch(noteRepositoryProvider).watch(shelf);

@riverpod
Stream<Note?> noteById(Ref ref, String id) =>
    ref.watch(noteRepositoryProvider).watchNote(id);

@riverpod
class NotesLayoutMode extends _$NotesLayoutMode {
  @override
  NotesLayout build() => NotesLayout.grid;

  void toggle() => state = state == NotesLayout.grid
      ? NotesLayout.list
      : NotesLayout.grid;
}
