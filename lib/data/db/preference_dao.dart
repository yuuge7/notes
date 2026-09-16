import 'package:drift/drift.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/db/tables.dart';

part 'preference_dao.g.dart';

/// Settings and one-off flags kept on this device, as text by key.
@DriftAccessor(tables: [Preferences])
class PreferenceDao extends DatabaseAccessor<AppDatabase>
    with _$PreferenceDaoMixin {
  PreferenceDao(super.attachedDatabase);

  static const theme = 'theme';
  static const checkedItems = 'checked_items';
  static const trashDays = 'trash_days';

  /// Set once the starter notes have been written, so they are written only
  /// on the first run rather than whenever the app finds no notes.
  static const seeded = 'seeded';

  /// Every stored value by key, now and after each change.
  Stream<Map<String, String>> watchAll() =>
      select(preferences)
          .watch()
          .map((rows) => {for (final row in rows) row.key: row.value});

  Future<Map<String, String>> readAll() async => {
    for (final row in await select(preferences).get()) row.key: row.value,
  };

  Future<String?> read(String key) async => (await (select(
    preferences,
  )..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

  Future<void> write(String key, String value) => into(
    preferences,
  ).insertOnConflictUpdate(PreferencesCompanion.insert(key: key, value: value));
}
