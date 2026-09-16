import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/db/preference_dao.dart';
import 'package:notes/data/repository/settings_repository.dart';
import 'package:notes/domain/model/settings.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository settings;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    settings = SettingsRepository(db.preferenceDao);
  });

  tearDown(() async {
    await db.close();
  });

  test('start from the defaults', () async {
    final loaded = await settings.load();

    expect(loaded.theme, ThemeChoice.system);
    expect(loaded.checkedItems, CheckedItems.folded);
    expect(loaded.trashRetention, TrashRetention.sevenDays);
  });

  test('keep what was chosen', () async {
    await settings.setTheme(ThemeChoice.dark);
    await settings.setCheckedItems(CheckedItems.inPlace);
    await settings.setTrashRetention(TrashRetention.thirtyDays);

    expect(
      await SettingsRepository(db.preferenceDao).load(),
      const AppSettings(
        theme: ThemeChoice.dark,
        checkedItems: CheckedItems.inPlace,
        trashRetention: TrashRetention.thirtyDays,
      ),
    );
  });

  test('read a value no longer understood as the default', () async {
    await db.preferenceDao.write(PreferenceDao.theme, 'sepia');
    await db.preferenceDao.write(PreferenceDao.trashDays, '12');
    await db.preferenceDao.write(PreferenceDao.checkedItems, '');

    expect(await settings.load(), const AppSettings());
  });

  test('tell watchers about each change, once', () async {
    final seen = <ThemeChoice>[];
    final subscription = settings.watch().listen((s) => seen.add(s.theme));
    await pumpEventQueue();

    await settings.setTheme(ThemeChoice.light);
    await pumpEventQueue();
    await settings.setTrashRetention(TrashRetention.oneDay);
    await pumpEventQueue();
    await settings.setTheme(ThemeChoice.dark);
    await pumpEventQueue();

    expect(seen, [
      ThemeChoice.system,
      ThemeChoice.light,
      ThemeChoice.light,
      ThemeChoice.dark,
    ]);
    await subscription.cancel();
  });
}
