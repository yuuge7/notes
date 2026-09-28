import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:notes/data/device/home_widgets.dart';
import 'package:notes/data/home_widgets/widget_snapshot.dart';
import 'package:notes/data/repository/note_repository.dart';
import 'package:notes/data/repository/settings_repository.dart';
import 'package:notes/domain/model/settings.dart';

/// The snapshot as it stands, for the note widgets showing [shown]. Read once,
/// where nothing is watching: a tick on a widget with the app closed.
Future<String> loadWidgetSnapshot(
  NoteRepository notes,
  SettingsRepository settings,
  Set<String> shown,
) async => encodeWidgetSnapshot(
  await notes.loadWidgetShelves(
    widgetNoteLimit,
    choices: widgetChoiceLimit,
    pages: shown,
  ),
  checkedItems: (await settings.load()).checkedItems,
);

/// Keeps the home screen widgets showing the notes as they are.
///
/// Like reminders, nothing that changes a note tells the widgets: this
/// watches the notes and hands Android a new snapshot whenever what any
/// widget could show would change, from any path that writes a note or a
/// label. A note widget placed or set to another note, and the setting that
/// places checked items, load the notes afresh.
class HomeWidgetSync {
  HomeWidgetSync(this._notes, this._settings, this._widgets);

  final NoteRepository _notes;
  final SettingsRepository _settings;
  final HomeWidgets _widgets;

  StreamSubscription<Set<String>>? _shownSubscription;
  StreamSubscription<CheckedItems>? _settingsSubscription;
  StreamSubscription<String>? _subscription;
  Set<String>? _shown;
  CheckedItems? _checkedItems;
  String? _published;
  Future<void> _queue = Future.value();

  /// Starts following the notes. The first snapshot goes out once the note
  /// widgets and the settings are known, so a widget placed before the app
  /// ever ran fills in when it first opens.
  void start() {
    _shownSubscription ??= _widgets.shownNotes.listen(
      (shown) {
        if (const SetEquality<String>().equals(shown, _shown)) return;
        _shown = shown;
        _follow();
      },
      onError: (Object error) {
        // Android could not say; the notes widgets still update, and each
        // note widget keeps its last snapshot.
        debugPrint('The note widgets are unknown: $error');
        _shown ??= const {};
        _follow();
      },
    );
    _settingsSubscription ??= _settings
        .watch()
        .map((settings) => settings.checkedItems)
        .distinct()
        .listen((checkedItems) {
          _checkedItems = checkedItems;
          _follow();
        });
  }

  /// Resolves once every snapshot handed over so far has landed.
  Future<void> get idle => _queue;

  Future<void> dispose() async {
    await _shownSubscription?.cancel();
    await _settingsSubscription?.cancel();
    await _subscription?.cancel();
    _shownSubscription = null;
    _settingsSubscription = null;
    _subscription = null;
  }

  /// Watches the notes for the note widgets and the setting as they are now,
  /// in place of what it watched before.
  void _follow() {
    final shown = _shown;
    final checkedItems = _checkedItems;
    if (shown == null || checkedItems == null) return;
    unawaited(_subscription?.cancel());
    _subscription = _notes
        .watchWidgetShelves(
          widgetNoteLimit,
          choices: widgetChoiceLimit,
          pages: shown,
        )
        .map(
          (shelves) =>
              encodeWidgetSnapshot(shelves, checkedItems: checkedItems),
        )
        .listen((snapshot) => unawaited(_publish(snapshot)));
  }

  /// Hands [snapshot] over unless it is the one already showing. Typing in a
  /// note rewrites it every few hundred milliseconds, often with nothing the
  /// widget shows changed, such as the edited time.
  Future<void> _publish(String snapshot) => _queue = _queue.then((_) async {
    if (snapshot == _published) return;
    try {
      await _widgets.publish(snapshot);
      _published = snapshot;
    } on Object catch (error) {
      // The widget keeps its last snapshot; the next change tries again.
      debugPrint('The home screen widgets were not updated: $error');
    }
  });
}
