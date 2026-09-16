import 'package:drift/drift.dart';
import 'package:notes/core/util/ids.dart';
import 'package:notes/core/util/sort_key.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/db/note_dao.dart';
import 'package:notes/data/db/preference_dao.dart';
import 'package:notes/domain/model/note_type.dart';
import 'package:notes/domain/model/pigment.dart';

/// First-run content, written once: on the first run of an install that
/// holds no notes. Deleting every note later, or replacing them all with an
/// empty import, does not bring the starter notes back.
///
/// Real sentences, not lorem: the grid only tells the truth about the design
/// when the cards hold the kind of text people actually capture — a two-word
/// reminder next to a paragraph next to a half-checked list.
Future<void> seedIfEmpty(NoteDao dao) async {
  final preferences = dao.attachedDatabase.preferenceDao;
  if (await preferences.read(PreferenceDao.seeded) != null) return;
  await dao.inTransaction(() async {
    if (await dao.countNotes() == 0) await _seed(dao);
    await preferences.write(PreferenceDao.seeded, 'true');
  });
}

Future<void> _seed(NoteDao dao) async {
  final now = DateTime.now();
  DateTime at(int daysAgo, int hour, int minute) => DateTime(
    now.year,
    now.month,
    now.day - daysAgo,
    hour,
    minute,
  );

  final home = _label('Home', 'm');
  final admin = _label('Admin', 'n');
  final reading = _label('Reading', 'o');
  for (final label in [home, admin, reading]) {
    await dao.upsertLabel(label);
  }

  final drafts = <_Draft>[
    _Draft(
      title: 'Flat viewing — Aurel Vlaicu 12',
      body:
          'Mihai shows it Thursday at 18:00. Ask whether the boiler was '
          'serviced this year and if the parking spot comes with the lease.',
      pigment: Pigment.verdigris,
      pinned: true,
      createdAt: at(0, 9, 12),
      labelIds: [home.id.value],
    ),
    _Draft(
      title: 'Groceries',
      type: NoteType.checklist,
      pigment: Pigment.amber,
      createdAt: at(0, 8, 40),
      items: const [
        ('Oat milk', false),
        ('Sourdough', false),
        ('Eggs', true),
        ('Coffee beans — the dark roast', false),
        ('Chili oil', true),
      ],
    ),
    _Draft(
      title: 'Renew passport',
      body: 'Appointment slots open at 07:00. Bring the old one and a photo.',
      pigment: Pigment.vermilion,
      createdAt: at(0, 7, 55),
      reminderAt: DateTime(now.year, now.month, now.day + 1, 9),
      labelIds: [admin.id.value],
    ),
    _Draft(
      title: '',
      body:
          'The hardest thing about writing is not the writing. It is sitting '
          'down at a fixed hour with nothing to say and staying there anyway.',
      pigment: Pigment.plum,
      createdAt: at(1, 22, 18),
      labelIds: [reading.id.value],
    ),
    _Draft(
      title: 'Bike',
      body: 'Rear brake pads are down to the metal.',
      pigment: Pigment.moss,
      createdAt: at(1, 17, 5),
    ),
    _Draft(
      title: 'The Peregrine — J.A. Baker',
      body:
          'Mentioned on the walk. Apparently the prose is the point, not the '
          'falcons. Library has one copy.',
      createdAt: at(1, 11, 30),
      labelIds: [reading.id.value],
    ),
    _Draft(
      title: 'Plants while away',
      type: NoteType.checklist,
      pigment: Pigment.indigo,
      createdAt: at(5, 20, 2),
      items: const [
        ('Move the fern off the sill', true),
        ('Water everything Sunday night', true),
        ('Leave the key with Ana', false),
      ],
    ),
    _Draft(
      title: 'Dentist',
      body: 'Dr. Pop, Tuesday 14:30. Entrance is from the courtyard.',
      pigment: Pigment.clay,
      createdAt: at(5, 9, 44),
      labelIds: [admin.id.value],
    ),
  ];

  // Keys descend with age so the newest capture sits at the top of the grid.
  var key = SortKey.first;
  for (final draft in drafts) {
    await _insert(dao, draft, key);
    key = SortKey.after(key);
  }
}

LabelsCompanion _label(String name, String sortKey) => LabelsCompanion.insert(
  id: newId(),
  name: name,
  sortKey: sortKey,
  updatedAtMs: DateTime.now().millisecondsSinceEpoch,
);

Future<void> _insert(NoteDao dao, _Draft draft, String sortKey) async {
  final id = newId();
  final ms = draft.createdAt.millisecondsSinceEpoch;
  await dao.insertNote(
    NotesCompanion.insert(
      id: id,
      sortKey: sortKey,
      createdAtMs: ms,
      updatedAtMs: ms,
      type: Value(draft.type),
      title: Value(draft.title),
      body: Value(draft.body),
      pigment: Value(draft.pigment),
      pinned: Value(draft.pinned),
      reminderAtMs: Value(draft.reminderAt?.millisecondsSinceEpoch),
    ),
  );

  var itemKey = SortKey.first;
  for (final (text, checked) in draft.items) {
    await dao.upsertItem(
      ChecklistItemsCompanion.insert(
        id: newId(),
        noteId: id,
        sortKey: itemKey,
        updatedAtMs: ms,
        content: Value(text),
        checked: Value(checked),
      ),
    );
    itemKey = SortKey.after(itemKey);
  }

  for (final labelId in draft.labelIds) {
    await dao.attachLabel(id, labelId);
  }
}

class _Draft {
  const _Draft({
    required this.title,
    required this.createdAt,
    this.body = '',
    this.type = NoteType.text,
    this.pigment = Pigment.graphite,
    this.pinned = false,
    this.reminderAt,
    this.items = const [],
    this.labelIds = const [],
  });

  final String title;
  final String body;
  final NoteType type;
  final Pigment pigment;
  final bool pinned;
  final DateTime createdAt;
  final DateTime? reminderAt;
  final List<(String, bool)> items;
  final List<String> labelIds;
}
