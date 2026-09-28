import 'dart:async';
import 'dart:convert';

import 'package:notes/data/device/home_widgets.dart';

/// Stands in for the launcher's widgets.
class FakeHomeWidgets implements HomeWidgets {
  FakeHomeWidgets({this.pinnable = true, this.launchAction});

  bool pinnable;

  /// The widget tap that started the app, handed out once.
  WidgetAction? launchAction;

  /// Every snapshot published, in order, decoded.
  final published = <Map<String, Object?>>[];

  /// Widgets the app asked the launcher to place, in order, with the feed a
  /// notes widget was to show.
  final pinned = <(HomeWidget, WidgetFeed)>[];

  /// Notes the app asked the launcher to place a note widget for, in order.
  final pinnedNotes = <String>[];

  final _actions = StreamController<WidgetAction>.broadcast();
  final _shown = StreamController<Set<String>>.broadcast();
  var _shownNow = <String>{};

  /// A widget tapped while the app runs.
  void tap(WidgetAction action) => _actions.add(action);

  /// Note widgets placed, set to other notes, or removed: [ids] are the
  /// notes they show now.
  void show(Set<String> ids) {
    _shownNow = ids;
    _shown.add(ids);
  }

  @override
  Future<void> publish(String snapshot) async =>
      published.add(jsonDecode(snapshot) as Map<String, Object?>);

  @override
  Future<WidgetAction?> takeLaunchAction() async {
    final action = launchAction;
    launchAction = null;
    return action;
  }

  @override
  Stream<WidgetAction> get actions => _actions.stream;

  @override
  Future<bool> canPin() async => pinnable;

  @override
  Future<void> pin(
    HomeWidget widget, {
    WidgetFeed feed = const AllFeed(),
  }) async => pinned.add((widget, feed));

  @override
  Future<void> pinNote(String noteId) async => pinnedNotes.add(noteId);

  @override
  Stream<Set<String>> get shownNotes async* {
    yield _shownNow;
    yield* _shown.stream;
  }
}
