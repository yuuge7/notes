import 'package:notes/data/providers.dart';
import 'package:notes/domain/model/label.dart';
import 'package:notes/domain/model/note_page.dart';
import 'package:notes/features/notes/notes_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'label_providers.g.dart';

/// Every label, in the order set on the labels page.
@riverpod
Stream<List<Label>> labels(Ref ref) =>
    ref.watch(labelRepositoryProvider).watchAll();

/// The notes on the grid wearing one label.
@riverpod
Stream<NotePage> labelNotes(Ref ref, String labelId) => ref
    .watch(labelRepositoryProvider)
    .watchNotesPage(labelId, ref.watch(noteWindowProvider('label:$labelId')));
