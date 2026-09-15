import 'package:flutter/foundation.dart';
import 'package:notes/domain/model/reminder_rule.dart';

/// What Android currently lets reminders do.
@immutable
class ReminderAccess {
  const ReminderAccess({
    required this.notifications,
    required this.exactAlarms,
  });

  static const granted = ReminderAccess(notifications: true, exactAlarms: true);

  /// Notifications are allowed for the app. Without them nothing rings.
  final bool notifications;

  /// Exact alarms are allowed. Without them Android rings reminders at an
  /// approximate time, which can be several minutes late.
  final bool exactAlarms;

  @override
  bool operator ==(Object other) =>
      other is ReminderAccess &&
      other.notifications == notifications &&
      other.exactAlarms == exactAlarms;

  @override
  int get hashCode => Object.hash(notifications, exactAlarms);
}

/// One notification, as it should be waiting to ring.
@immutable
class ScheduledReminder {
  const ScheduledReminder({
    required this.id,
    required this.noteId,
    required this.title,
    required this.body,
    required this.at,
    required this.setFor,
    required this.exact,
    this.repeat,
  });

  /// The notification's number; see [ReminderIds].
  final int id;

  /// Carried by the notification, so a tap opens this note.
  final String noteId;
  final String title;
  final String body;

  /// The next ring. With [repeat] set, a time the repeat matches.
  final DateTime at;

  /// The reminder time stored on the note when this was scheduled. The
  /// notification carries it, so its buttons can tell whether the reminder
  /// has been moved since it rang.
  final DateTime setFor;

  /// How the notification repeats after [at], or null to ring once.
  final ReminderRule? repeat;

  /// Whether to ring on the minute, or let Android choose a nearby time.
  final bool exact;

  @override
  bool operator ==(Object other) =>
      other is ScheduledReminder &&
      other.id == id &&
      other.noteId == noteId &&
      other.title == title &&
      other.body == body &&
      other.at == at &&
      other.setFor == setFor &&
      other.repeat == repeat &&
      other.exact == exact;

  @override
  int get hashCode =>
      Object.hash(id, noteId, title, body, at, setFor, repeat, exact);

  @override
  String toString() =>
      'ScheduledReminder($id, $noteId, "$title", "$body", $at, '
      '${repeat?.name ?? 'once'}, ${exact ? 'exact' : 'inexact'})';
}

/// How reminder notifications are numbered.
///
/// A note's reminder rings under the note's row id. A snooze of a repeating
/// reminder rings under a second id of its own, so it does not replace the
/// repeat.
abstract final class ReminderIds {
  static const int _snoozeOffset = 1 << 30;

  static int snoozeOf(int id) => id + _snoozeOffset;

  static bool isSnooze(int id) => id >= _snoozeOffset;
}

/// What a reminder notification carries back when it is tapped or its
/// buttons are pressed: the note, and the reminder time it was scheduled
/// with.
@immutable
class ReminderPayload {
  const ReminderPayload(this.noteId, this.setFor);

  final String noteId;

  /// Null for a payload that carries only the note.
  final DateTime? setFor;

  String encode() {
    final setFor = this.setFor;
    return setFor == null
        ? noteId
        : '$noteId|${setFor.millisecondsSinceEpoch}';
  }

  /// Reads a payload written by [encode], or null for an empty one.
  static ReminderPayload? decode(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    final bar = payload.indexOf('|');
    if (bar < 0) return ReminderPayload(payload, null);
    final ms = int.tryParse(payload.substring(bar + 1));
    return ReminderPayload(
      payload.substring(0, bar),
      ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReminderPayload &&
      other.noteId == noteId &&
      other.setFor == setFor;

  @override
  int get hashCode => Object.hash(noteId, setFor);
}

/// Hands reminders to the system's alarms and notifications.
abstract interface class ReminderScheduler {
  Future<ReminderAccess> access();

  /// Asks for permission to notify, where Android still offers the prompt,
  /// and reports whether notifications are allowed afterwards.
  Future<bool> requestNotifications();

  /// Opens the system page where exact alarms are allowed.
  Future<void> requestExactAlarms();

  /// Opens the app's notification settings, for when the prompt is no longer
  /// offered.
  Future<void> openNotificationSettings();

  /// Schedules [reminder], replacing whatever waits under its id.
  Future<void> schedule(ScheduledReminder reminder);

  /// Cancels the notification with [id], whether waiting or on screen.
  Future<void> cancel(int id);

  /// The ids of every notification still waiting to ring.
  Future<Set<int>> pendingIds();
}
