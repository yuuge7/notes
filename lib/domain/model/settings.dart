import 'package:freezed_annotation/freezed_annotation.dart';

part 'settings.freezed.dart';

/// Which theme the app wears.
enum ThemeChoice {
  system('System default'),
  light('Light'),
  dark('Dark');

  ThemeChoice(this.label);

  final String label;
}

/// Where a checklist keeps the items that are ticked off.
enum CheckedItems {
  /// Under an "n checked items" count at the bottom, folded away.
  folded('Fold away at the bottom', 'Out of sight under a count until opened'),

  /// Under the same count at the bottom, open from the start.
  shown('Show at the bottom', 'Listed below the open items, struck through'),

  /// Where they were, struck through.
  inPlace('Leave in place', 'Struck through where they are, in list order');

  CheckedItems(this.label, this.detail);

  final String label;
  final String detail;

  /// Whether ticked items leave their place for a section of their own.
  bool get atBottom => this != inPlace;
}

/// How long a note stays in the trash before it is deleted for good.
enum TrashRetention {
  oneDay(1),
  sevenDays(7),
  thirtyDays(30);

  TrashRetention(this.days);

  final int days;

  Duration get duration => Duration(days: days);

  String get label => days == 1 ? '1 day' : '$days days';

  /// The stay for [days], or null when no choice lasts that long.
  static TrashRetention? ofDays(int days) {
    for (final retention in values) {
      if (retention.days == days) return retention;
    }
    return null;
  }
}

/// Everything chosen on the settings page.
@freezed
abstract class AppSettings with _$AppSettings {
  const factory AppSettings({
    @Default(ThemeChoice.system) ThemeChoice theme,
    @Default(CheckedItems.folded) CheckedItems checkedItems,
    @Default(TrashRetention.sevenDays) TrashRetention trashRetention,
  }) = _AppSettings;
}
