import 'package:collection/collection.dart';
import 'package:notes/data/db/preference_dao.dart';
import 'package:notes/domain/model/settings.dart';

/// Reads and changes the settings chosen on this device.
///
/// A value that is missing or no longer understood reads as the default, so
/// a setting dropped in a later version cannot stop the app from starting.
class SettingsRepository {
  SettingsRepository(this._dao);

  final PreferenceDao _dao;

  Stream<AppSettings> watch() => _dao.watchAll().map(_fromValues).distinct();

  Future<AppSettings> load() async => _fromValues(await _dao.readAll());

  Future<void> setTheme(ThemeChoice theme) =>
      _dao.write(PreferenceDao.theme, theme.name);

  Future<void> setCheckedItems(CheckedItems checkedItems) =>
      _dao.write(PreferenceDao.checkedItems, checkedItems.name);

  Future<void> setTrashRetention(TrashRetention retention) =>
      _dao.write(PreferenceDao.trashDays, '${retention.days}');

  static AppSettings _fromValues(Map<String, String> values) {
    T? named<T extends Enum>(List<T> choices, String key) =>
        choices.firstWhereOrNull((choice) => choice.name == values[key]);

    const defaults = AppSettings();
    return AppSettings(
      theme: named(ThemeChoice.values, PreferenceDao.theme) ?? defaults.theme,
      checkedItems:
          named(CheckedItems.values, PreferenceDao.checkedItems) ??
          defaults.checkedItems,
      trashRetention:
          TrashRetention.ofDays(
            int.tryParse(values[PreferenceDao.trashDays] ?? '') ?? 0,
          ) ??
          defaults.trashRetention,
    );
  }
}
