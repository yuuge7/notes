import 'package:notes/data/db/note_dao.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/data/seed.dart';
import 'package:notes/domain/model/note.dart';
import 'package:notes/domain/model/note_page.dart';
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

/// How many notes a shelf loads at first, and how many more each time its
/// end comes near.
const notePageSize = 100;

/// How many notes a shelf, or a label's page, has loaded so far. Starts again
/// at one page when the screen leaves.
@riverpod
class NoteWindow extends _$NoteWindow {
  @override
  int build(String shelf) => notePageSize;

  void grow() => state += notePageSize;
}

@riverpod
Stream<NotePage> shelfNotes(Ref ref, Shelf shelf) => ref
    .watch(noteRepositoryProvider)
    .watchPage(shelf, ref.watch(noteWindowProvider(shelf.name)));

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
