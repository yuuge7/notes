import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/repository/label_repository.dart';
import 'package:notes/data/repository/search_repository.dart';
import 'package:notes/data/repository/settings_repository.dart';
import 'package:notes/data/seed.dart';
import 'package:notes/domain/model/search.dart';
import 'package:notes/domain/model/settings.dart';

import 'schema_v1.dart';
import 'schema_v2.dart';

Future<List<String>> _schemaOf(AppDatabase db) async => [
  for (final row
      in await db
          .customSelect(
            "SELECT type || ' ' || name AS entry FROM sqlite_master "
            "WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name",
          )
          .get())
    row.read<String>('entry'),
];

AppDatabase _fresh() {
  final db = AppDatabase(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
  );
  addTearDown(db.close);
  return db;
}

void main() {
  group('from version 1', _fromVersion1);
  group('from version 2', _fromVersion2);
}

/// An install from before labels and search, upgraded in place.
void _fromVersion1() {
  late AppDatabase upgraded;

  setUp(() {
    upgraded = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(
          setup: (raw) {
            schemaV1.forEach(raw.execute);
            raw
              ..execute(
                'INSERT INTO notes (id, title, body, sort_key, '
                'created_at_ms, updated_at_ms) '
                "VALUES ('n1', 'Bike', 'Rear brake pads', 'n', 0, 0)",
              )
              ..execute(
                'INSERT INTO checklist_items '
                '(id, note_id, text, sort_key, updated_at_ms) '
                "VALUES ('i1', 'n1', 'Chain oil', 'n', 0)",
              )
              ..execute(
                'INSERT INTO labels (id, name, sort_key, updated_at_ms) '
                "VALUES ('l1', 'Garage', 'n', 0)",
              )
              ..execute(
                'INSERT INTO note_labels (note_id, label_id, updated_at_ms) '
                "VALUES ('n1', 'l1', 0)",
              )
              ..userVersion = 1;
          },
        ),
        closeStreamsSynchronously: true,
      ),
    );
  });

  tearDown(() async {
    await upgraded.close();
  });

  test('keeps every note, item, and label', () async {
    final note = (await upgraded.noteDao.loadNote('n1'))!;

    expect(note.title, 'Bike');
    expect([for (final item in note.items) item.text], ['Chain oil']);
    expect([for (final label in note.labels) label.name], ['Garage']);
  });

  test('indexes existing notes for search', () async {
    final search = SearchRepository(upgraded.searchDao);

    for (final word in ['bike', 'brake', 'chain', 'garage']) {
      final results = await search.search(SearchQuery(text: word));
      expect([for (final note in results.notes) note.id], ['n1'], reason: word);
    }
  });

  test('label names become unique ignoring case', () async {
    final labels = LabelRepository(upgraded.noteDao);

    expect((await labels.create('garage')).id, 'l1');
    await expectLater(
      upgraded.noteDao.upsertLabel(
        LabelsCompanion.insert(
          id: 'l2',
          name: 'GARAGE',
          sortKey: 'o',
          updatedAtMs: 0,
        ),
      ),
      throwsA(anything),
    );
    // A deleted label's name is free again.
    await upgraded.noteDao.updateLabel(
      'l1',
      const LabelsCompanion(deleted: Value(true)),
    );
    expect((await labels.create('Garage')).id, isNot('l1'));
  });

  test('ends with the same tables, indexes, and triggers as a new install', () async {
    expect(await _schemaOf(upgraded), await _schemaOf(_fresh()));
  });
}

/// An install from before settings, upgraded in place.
void _fromVersion2() {
  late AppDatabase upgraded;

  AppDatabase open({required bool withNotes}) => AppDatabase(
    DatabaseConnection(
      NativeDatabase.memory(
        setup: (raw) {
          schemaV2.forEach(raw.execute);
          if (withNotes) {
            raw.execute(
              'INSERT INTO notes (id, title, body, sort_key, '
              'created_at_ms, updated_at_ms) '
              "VALUES ('n1', 'Bike', 'Rear brake pads', 'n', 0, 0)",
            );
          }
          raw.userVersion = 2;
        },
      ),
      closeStreamsSynchronously: true,
    ),
  );

  tearDown(() async {
    await upgraded.close();
  });

  test('keeps notes, and search still finds them', () async {
    upgraded = open(withNotes: true);

    expect((await upgraded.noteDao.loadNote('n1'))!.title, 'Bike');
    final results = await SearchRepository(
      upgraded.searchDao,
    ).search(const SearchQuery(text: 'brake'));
    expect([for (final note in results.notes) note.id], ['n1']);
  });

  test('starts every setting at its default', () async {
    upgraded = open(withNotes: true);

    expect(
      await SettingsRepository(upgraded.preferenceDao).load(),
      const AppSettings(),
    );
  });

  test('does not write the starter notes into an install whose notes are all gone', () async {
    upgraded = open(withNotes: false);

    await seedIfEmpty(upgraded.noteDao);

    expect(await upgraded.noteDao.countNotes(), 0);
  });

  test('ends with the same tables, indexes, and triggers as a new install', () async {
    upgraded = open(withNotes: false);

    expect(await _schemaOf(upgraded), await _schemaOf(_fresh()));
  });
}
