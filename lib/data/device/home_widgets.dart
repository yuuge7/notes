import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The app's widgets for the home screen.
enum HomeWidget {
  /// The notes of one [WidgetFeed], as the grid orders them.
  notes,

  /// The compose bar: a note, a list, photos, or the camera.
  capture,
}

/// Which notes a notes widget shows, chosen as it is placed and changed from
/// the widget's settings. Android keeps the choice for each widget by [key].
@immutable
sealed class WidgetFeed {
  const WidgetFeed();

  /// Reads a feed as Android keeps it, or null for one this version does not
  /// know.
  static WidgetFeed? decode(Object? key) => switch (key) {
    'all' => const AllFeed(),
    'pinned' => const PinnedFeed(),
    final String key
        when key.startsWith(LabelFeed._prefix) &&
            key.length > LabelFeed._prefix.length =>
      LabelFeed(key.substring(LabelFeed._prefix.length)),
    _ => null,
  };

  String get key;

  @override
  bool operator ==(Object other) => other is WidgetFeed && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// Pinned notes, then the latest: the grid's own order.
class AllFeed extends WidgetFeed {
  const AllFeed();

  /// How the widget's settings offer it, in the app and on the home screen.
  static const name = 'All notes';

  @override
  String get key => 'all';
}

/// Only the pinned notes.
class PinnedFeed extends WidgetFeed {
  const PinnedFeed();

  /// How the widget's settings offer it, in the app and on the home screen.
  static const name = 'Pinned notes';

  @override
  String get key => 'pinned';
}

/// The notes wearing one label, as on that label's page.
class LabelFeed extends WidgetFeed {
  const LabelFeed(this.labelId);

  static const _prefix = 'label:';

  final String labelId;

  @override
  String get key => '$_prefix$labelId';
}

/// What a tap on a home screen widget asks the app to do.
@immutable
sealed class WidgetAction {
  const WidgetAction();

  /// Reads an action as the platform sends it, or null for one this version
  /// does not know.
  static WidgetAction? decode(Object? message) {
    if (message is! Map) return null;
    final feed = WidgetFeed.decode(message['feed']);
    return switch (message['action']) {
      'open' when message['noteId'] is String => OpenNote(
        message['noteId'] as String,
      ),
      'newNote' => NewNote(feed: feed ?? const AllFeed()),
      'newList' => const NewList(),
      'addPhotos' => const AddPhotos(),
      'takePhoto' => const TakePhoto(),
      'showFeed' when feed != null => ShowFeed(feed),
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

/// The + on a notes widget, or Take a note on the new note widget. A note
/// started from a widget showing one label wears it, and one started from the
/// pinned widget is pinned, so the note lands on the widget it came from.
class NewNote extends WidgetAction {
  const NewNote({this.feed = const AllFeed()});

  final WidgetFeed feed;

  @override
  bool operator ==(Object other) => other is NewNote && other.feed == feed;

  @override
  int get hashCode => feed.hashCode;
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

/// The heading of a notes widget: the app, at the page the widget mirrors.
class ShowFeed extends WidgetAction {
  const ShowFeed(this.feed);

  final WidgetFeed feed;

  @override
  bool operator ==(Object other) => other is ShowFeed && other.feed == feed;

  @override
  int get hashCode => feed.hashCode;
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
  /// shows its own confirmation. A notes widget shows [feed].
  Future<void> pin(HomeWidget widget, {WidgetFeed feed = const AllFeed()});
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
  Future<void> pin(HomeWidget widget, {WidgetFeed feed = const AllFeed()}) =>
      _channel.invokeMethod<void>('pin', {
        'widget': widget.name,
        'feed': feed.key,
      });
}
