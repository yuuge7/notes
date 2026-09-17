import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The app's widgets for the home screen.
enum HomeWidget {
  /// Pinned notes, then the latest, as the grid orders them.
  notes,

  /// The compose bar: a note, a list, photos, or the camera.
  capture,
}

/// What a tap on a home screen widget asks the app to do.
@immutable
sealed class WidgetAction {
  const WidgetAction();

  /// Reads an action as the platform sends it, or null for one this version
  /// does not know.
  static WidgetAction? decode(Object? message) {
    if (message is! Map) return null;
    return switch (message['action']) {
      'open' when message['noteId'] is String => OpenNote(
        message['noteId'] as String,
      ),
      'newNote' => const NewNote(),
      'newList' => const NewList(),
      'addPhotos' => const AddPhotos(),
      'takePhoto' => const TakePhoto(),
      _ => null,
    };
  }
}

class OpenNote extends WidgetAction {
  const OpenNote(this.noteId);

  final String noteId;

  @override
  bool operator ==(Object other) => other is OpenNote && other.noteId == noteId;

  @override
  int get hashCode => noteId.hashCode;
}

class NewNote extends WidgetAction {
  const NewNote();
}

class NewList extends WidgetAction {
  const NewList();
}

class AddPhotos extends WidgetAction {
  const AddPhotos();
}

class TakePhoto extends WidgetAction {
  const TakePhoto();
}

/// The home screen widgets, as far as the app reaches them: what they show,
/// and the taps that open the app.
abstract interface class HomeWidgets {
  /// Hands Android the notes the widgets show, as written by
  /// `encodeWidgetSnapshot`. The widgets redraw from it, and keep showing it
  /// while the app is closed.
  Future<void> publish(String snapshot);

  /// The action of the widget tap that started the app, if one did. Given
  /// once: a second call returns null.
  Future<WidgetAction?> takeLaunchAction();

  /// Widget taps that arrive while the app is running.
  Stream<WidgetAction> get actions;

  /// Whether the launcher lets the app place a widget itself, after asking.
  Future<bool> canPin();

  /// Asks the launcher to place [widget] on the home screen. The launcher
  /// shows its own confirmation.
  Future<void> pin(HomeWidget widget);
}

/// Android, reached through MainActivity.
class DeviceHomeWidgets implements HomeWidgets {
  DeviceHomeWidgets() {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'action') return;
      final action = WidgetAction.decode(call.arguments);
      if (action != null) _actions.add(action);
    });
  }

  static const _channel = MethodChannel('com.ionel.notes/widgets');

  final _actions = StreamController<WidgetAction>.broadcast();

  @override
  Future<void> publish(String snapshot) =>
      _channel.invokeMethod<void>('publish', {'snapshot': snapshot});

  @override
  Future<WidgetAction?> takeLaunchAction() async =>
      WidgetAction.decode(await _channel.invokeMethod<Object?>('takeAction'));

  @override
  Stream<WidgetAction> get actions => _actions.stream;

  @override
  Future<bool> canPin() async =>
      await _channel.invokeMethod<bool>('canPin') ?? false;

  @override
  Future<void> pin(HomeWidget widget) =>
      _channel.invokeMethod<void>('pin', {'widget': widget.name});
}
