import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:notes/data/db/backup_dao.dart';
import 'package:notes/data/db/note_dao.dart';
import 'package:notes/data/db/preference_dao.dart';
import 'package:notes/data/db/search_dao.dart';
import 'package:notes/data/db/search_index.dart';
import 'package:notes/data/db/tables.dart';
// The generated part refers to the column enums by name, and a part only sees
// this file's imports.
import 'package:notes/domain/model/note_type.dart';
import 'package:notes/domain/model/pigment.dart';
import 'package:notes/domain/model/reminder_rule.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Notes,
    ChecklistItems,
    Labels,
    NoteLabels,
    Attachments,
    RecentSearches,
    Preferences,
  ],
  daos: [NoteDao, SearchDao, PreferenceDao, BackupDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(
        executor ??
            driftDatabase(
              name: 'notes',
              // Done and Snooze on a notification write from an isolate of
              // their own, often while the app is open. One shared
              // connection keeps those writes in step with the app's, and
              // the app's lists update the moment they land.
              native: const DriftNativeOptions(shareAcrossIsolates: true),
            ),
      );

  /// 1: notes, items, labels, attachments.
  /// 2: full-text search, recent searches, and label names unique among live
  ///    labels ignoring case.
  /// 3: preferences.
  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await SearchIndex.install(customStatement);
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // Version 1 made names unique with a column constraint, which counted
        // case and deleted labels. SQLite cannot drop a constraint in place,
        // so the table is rebuilt without it and the partial index takes
        // over. Foreign keys are still off here; they come on before open.
        await m.alterTable(TableMigration(labels));
        await m.createIndex(idxLabelsName);
        await m.createTable(recentSearches);
        await SearchIndex.install(customStatement);
      }
      if (from < 3) {
        await m.createTable(preferences);
        // Every earlier install wrote the starter notes on its first run.
        // Without this, one whose notes were all deleted would get them again.
        await preferenceDao.write(PreferenceDao.seeded, 'true');
      }
    },
    beforeOpen: (details) async {
      // Cascades keep items, labels links, and attachments from outliving
      // their note.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
