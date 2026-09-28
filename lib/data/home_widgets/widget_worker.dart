import 'dart:async';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/device/home_widgets.dart';
import 'package:notes/data/home_widgets/home_widget_sync.dart';
import 'package:notes/data/repository/checklist_repository.dart';
import 'package:notes/data/repository/note_repository.dart';
import 'package:notes/data/repository/settings_repository.dart';

/// Where the home screen widgets reach the notes with no screen: Android runs
/// this in a Flutter engine of its own (WidgetWorker.kt) the first time a
/// note widget needs it, whether or not the app is open, and keeps it for the
/// next tap.
///
/// main.dart exports this, which keeps it in the build: nothing in the app
/// calls it.
@pragma('vm:entry-point')
Future<void> widgetWorker() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final worker = WidgetWorker(AppDatabase.new, DeviceHomeWidgets());
  const channel = MethodChannel('com.ionel.notes/widget_worker');
  channel.setMethodCallHandler((call) async {
    final arguments = call.arguments;
    switch (call.method) {
      case 'setChecked' when arguments is Map:
        await worker.setChecked(
          arguments['noteId'] as String,
          arguments['itemId'] as String,
          checked: arguments['checked'] as bool,
        );
      case 'refresh':
        await worker.refresh();
      default:
        throw MissingPluginException();
    }
  });
  await channel.invokeMethod<void>('ready');
}

/// Ticks items off from a note widget, and hands the widgets a snapshot once
/// it has.
///
/// Opens the database for each run and closes it after, as a notification's
/// Done does: while the app runs, the connection is the app's own, so the
/// grid and an open note see the tick at once.
class WidgetWorker {
  WidgetWorker(this._open, this._widgets);

  final AppDatabase Function() _open;
  final HomeWidgets _widgets;

  final _checks = <({String noteId, String itemId, bool checked})>[];
  Future<void> _busy = Future.value();
  Future<void>? _next;

  /// Checks or unchecks an item, with its children as in the editor. Taps
  /// that come while a run is busy go in the next together, in the order
  /// made, with one snapshot for all of them.
  Future<void> setChecked(
    String noteId,
    String itemId, {
    required bool checked,
  }) {
    _checks.add((noteId: noteId, itemId: itemId, checked: checked));
    return _schedule();
  }

  /// Hands the widgets a fresh snapshot, as when a note widget has just been
  /// set to a note the last one did not carry.
  Future<void> refresh() => _schedule();

  Future<void> _schedule() {
    final next = _next;
    if (next != null) return next;
    final run = _busy.then((_) {
      _next = null;
      return _run();
    });
    _next = run;
    _busy = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<void> _run() async {
    final checks = [..._checks];
    _checks.clear();
    final db = _open();
    try {
      final notes = NoteRepository(db.noteDao);
      final lists = ChecklistRepository(db.noteDao);
      for (final (:noteId, :itemId, :checked) in checks) {
        // A widget drawn before the note went to the trash, or stopped being
        // a list, leaves it alone.
        final note = await notes.load(noteId);
        if (note == null || note.deleted || !note.isChecklist) continue;
        await lists.setChecked(noteId, itemId, checked: checked);
      }
      final shown = await _widgets.shownNotes.first;
      await _widgets.publish(
        await loadWidgetSnapshot(
          notes,
          SettingsRepository(db.preferenceDao),
          shown,
        ),
      );
    } on Object catch (error) {
      debugPrint('A home screen widget could not reach the notes: $error');
      rethrow;
    } finally {
      await db.close();
    }
  }
}
