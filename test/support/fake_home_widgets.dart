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

  /// Widgets the app asked the launcher to place, in order.
  final pinned = <HomeWidget>[];

  final _actions = StreamController<WidgetAction>.broadcast();

  /// A widget tapped while the app runs.
  void tap(WidgetAction action) => _actions.add(action);

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
  Future<void> pin(HomeWidget widget) async => pinned.add(widget);
}
