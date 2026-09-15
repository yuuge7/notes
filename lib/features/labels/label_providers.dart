import 'package:notes/data/providers.dart';
import 'package:notes/domain/model/label.dart';
import 'package:notes/domain/model/note.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'label_providers.g.dart';

/// Every label, in the order set on the labels page.
@riverpod
Stream<List<Label>> labels(Ref ref) =>
    ref.watch(labelRepositoryProvider).watchAll();

/// The notes on the grid wearing one label.
@riverpod
Stream<List<Note>> labelNotes(Ref ref, String labelId) =>
    ref.watch(labelRepositoryProvider).watchNotes(labelId);
