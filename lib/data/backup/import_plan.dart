import 'package:notes/core/util/sort_key.dart';
import 'package:notes/data/backup/bundle.dart';
import 'package:notes/data/repository/label_repository.dart';
import 'package:notes/domain/model/label.dart';
import 'package:notes/domain/model/note.dart';

/// How an import meets the notes already on the phone.
enum ImportMode {
  /// Notes in both keep whichever was edited last; the rest are added.
  merge,

  /// Every note and label here is deleted, and the file's take their place.
  replace,
}

/// What an import needs to know about the notes already on the phone.
class LocalState {
  const LocalState({
    this.notes = const {},
    this.labels = const [],
    this.imageIds = const {},
  });

  /// Every note, trashed ones included: when it was last edited, and where it
  /// sits.
  final Map<String, ({DateTime updatedAt, String sortKey})> notes;

  /// Every label, deleted ones included.
  final List<({Label label, bool deleted})> labels;

  /// Images on notes that have not been removed.
  final Set<String> imageIds;
}

/// A note to write, with the ids of the labels on this phone it wears.
typedef PlannedNote = ({Note note, List<String> labelIds});

/// What an import will do, worked out before anything is written.
///
/// The same plan serves as the summary shown before the import and as the
/// list of writes the import makes, worked out again inside its transaction,
/// so what is shown is what happens.
class ImportPlan {
  const ImportPlan({
    required this.mode,
    required this.labels,
    required this.notes,
    this.notesAdded = 0,
    this.notesUpdated = 0,
    this.notesKept = 0,
    this.notesRemoved = 0,
    this.labelsAdded = 0,
    this.imagesAdded = 0,
    this.imagesMissing = 0,
  });

  /// Works out how [bundle] meets [local] under [mode].
  factory ImportPlan.of(Bundle bundle, LocalState local, ImportMode mode) {
    return switch (mode) {
      ImportMode.merge => _merge(bundle, local),
      ImportMode.replace => _replace(bundle, local),
    };
  }

  final ImportMode mode;

  /// Labels to write, as they will be stored.
  final List<Label> labels;

  /// Notes to write, as they will be stored.
  final List<PlannedNote> notes;

  /// Notes new to this phone.
  final int notesAdded;

  /// Notes here that the file holds a later edit of.
  final int notesUpdated;

  /// Notes here edited at the same time as, or after, the file's copy.
  final int notesKept;

  /// Notes here that a replace deletes.
  final int notesRemoved;
  final int labelsAdded;
  final int imagesAdded;

  /// Images the file should hold but does not.
  final int imagesMissing;

  static ImportPlan _replace(Bundle bundle, LocalState local) {
    final labels = _Labels(const LocalState());
    for (final label in bundle.labels) {
      labels.add(label, sortKey: label.sortKey);
    }
    return ImportPlan(
      mode: ImportMode.replace,
      labels: labels.writes,
      notes: [
        for (final note in bundle.notes)
          (note: note, labelIds: labels.idsFor(note)),
      ],
      notesAdded: bundle.notes.length,
      notesRemoved: local.notes.length,
      labelsAdded: labels.writes.length,
      imagesAdded: bundle.imageCount,
      imagesMissing: bundle.missingImages,
    );
  }

  static ImportPlan _merge(Bundle bundle, LocalState local) {
    final labels = _Labels(local);
    bundle.labels.forEach(labels.merge);

    final added = <Note>[];
    final updated = <Note>[];
    var kept = 0;
    for (final note in bundle.notes) {
      final here = local.notes[note.id];
      if (here == null) {
        added.add(note);
      } else if (note.updatedAt.isAfter(here.updatedAt)) {
        // An updated note keeps its place among the notes here.
        updated.add(note.copyWith(sortKey: here.sortKey));
      } else {
        kept++;
      }
    }

    // New notes go above every note here, in the order the file has them.
    // Their own keys come from another phone's order and could tie with keys
    // here, so they get new ones.
    added.sort((a, b) => a.sortKey.compareTo(b.sortKey));
    final lowest = local.notes.values
        .map((note) => note.sortKey)
        .fold<String?>(
          null,
          (low, key) => low == null || key.compareTo(low) < 0 ? key : low,
        );
    final keys = SortKey.spread(added.length, before: lowest ?? '');
    final writes = [
      for (final (index, note) in added.indexed)
        note.copyWith(sortKey: keys[index]),
      ...updated,
    ];

    return ImportPlan(
      mode: ImportMode.merge,
      labels: labels.writes,
      notes: [
        for (final note in writes) (note: note, labelIds: labels.idsFor(note)),
      ],
      notesAdded: added.length,
      notesUpdated: updated.length,
      notesKept: kept,
      labelsAdded: labels.added,
      imagesAdded: writes.fold(
        0,
        (sum, note) =>
            sum +
            note.attachments
                .where((image) => !local.imageIds.contains(image.id))
                .length,
      ),
      imagesMissing: bundle.missingImages,
    );
  }
}

/// Matches the file's labels to the labels here.
///
/// Names are unique among live labels ignoring case, as the database's index
/// has it, so a file's label named like a label here becomes that label
/// rather than a second one.
class _Labels {
  _Labels(LocalState local)
    : _byId = {for (final entry in local.labels) entry.label.id: entry},
      _live = {
        for (final entry in local.labels)
          if (!entry.deleted) _fold(entry.label.name): entry.label.id,
      },
      // Deleted labels count too: one restored by undo keeps its old key.
      _lastKey = local.labels
          .map((entry) => entry.label.sortKey)
          .fold<String?>(
            null,
            (last, key) => last == null || key.compareTo(last) > 0 ? key : last,
          );

  final Map<String, ({Label label, bool deleted})> _byId;

  /// Live label ids by folded name.
  final Map<String, String> _live;
  String? _lastKey;

  /// The file's label ids, to the ids of the labels here they became.
  final _ids = <String, String>{};
  final writes = <Label>[];
  int added = 0;

  /// SQLite's NOCASE, which the unique index on names uses, folds ASCII
  /// letters only.
  static String _fold(String name) => name.replaceAllMapped(
    RegExp('[A-Z]'),
    (match) => match[0]!.toLowerCase(),
  );

  /// Takes [label] as it is, at [sortKey], unless a label written before it
  /// already has its name.
  void add(Label label, {required String sortKey}) {
    final name = LabelRepository.cleanName(label.name);
    if (name == null) return;
    final twin = _live[_fold(name)];
    if (twin != null) {
      _ids[label.id] = twin;
      return;
    }
    writes.add(label.copyWith(name: name, sortKey: sortKey));
    _live[_fold(name)] = label.id;
    _ids[label.id] = label.id;
  }

  /// Takes [label] where it is newer than the label here, or new here.
  void merge(Label label) {
    final name = LabelRepository.cleanName(label.name);
    if (name == null) return;
    final here = _byId[label.id];
    final twin = _live[_fold(name)];

    if (here == null) {
      if (twin != null) {
        _ids[label.id] = twin;
        return;
      }
      final key = _lastKey == null ? SortKey.first : SortKey.after(_lastKey!);
      _lastKey = key;
      writes.add(label.copyWith(name: name, sortKey: key));
      _live[_fold(name)] = label.id;
      _ids[label.id] = label.id;
      added++;
      return;
    }

    _ids[label.id] = label.id;
    // The label here was edited last, or its name is taken by another label:
    // it stays as it is. A label deleted here stays deleted.
    if (!label.updatedAt.isAfter(here.label.updatedAt)) return;
    if (twin != null && twin != label.id) {
      _ids[label.id] = twin;
      return;
    }
    if (!here.deleted && here.label.name == name) return;

    if (!here.deleted) _live.remove(_fold(here.label.name));
    _live[_fold(name)] = label.id;
    writes.add(here.label.copyWith(name: name, updatedAt: label.updatedAt));
    if (here.deleted) added++;
  }

  /// The ids of the labels here that [note] wears, once each.
  List<String> idsFor(Note note) =>
      {for (final label in note.labels) ?_ids[label.id]}.toList();
}
