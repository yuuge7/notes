import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:notes/data/device/home_widgets.dart';
import 'package:notes/data/home_widgets/widget_snapshot.dart';
import 'package:notes/data/repository/note_repository.dart';

/// Keeps the home screen widgets showing the notes as they are.
///
/// Like reminders, nothing that changes a note tells the widgets: this
/// watches the notes and hands Android a new snapshot whenever what any
/// widget could show would change, from any path that writes a note or a
/// label.
class HomeWidgetSync {
  HomeWidgetSync(this._notes, this._widgets);

  final NoteRepository _notes;
  final HomeWidgets _widgets;

  StreamSubscription<String>? _subscription;
  String? _published;
  Future<void> _queue = Future.value();

  /// Starts following the notes. The first snapshot goes out at once, so a
  /// widget placed before the app ever ran fills in when it first opens.
  void start() {
    _subscription ??= _notes
        .watchWidgetShelves(widgetNoteLimit)
        .map(encodeWidgetSnapshot)
        .listen((snapshot) => unawaited(_publish(snapshot)));
  }

  /// Resolves once every snapshot handed over so far has landed.
  Future<void> get idle => _queue;

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
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
