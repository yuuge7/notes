import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:notes/core/theme/app_colors.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/reminders/reminder_actions.dart';
import 'package:notes/data/repository/reminder_repository.dart';
import 'package:notes/domain/model/reminder_rule.dart';
import 'package:notes/domain/service/reminder_scheduler.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Done or Snooze pressed on a reminder notification, or the notification
/// swiped away.
///
/// The plugin runs this on an isolate of its own whether or not the app is
/// open, so it opens the database itself; while the app runs, that
/// connection is shared with the app's.
@pragma('vm:entry-point')
Future<void> handleReminderAction(NotificationResponse response) async {
  final payload = ReminderPayload.decode(response.payload);
  if (payload == null) return;
  final scheduler = NotificationReminderScheduler();
  await scheduler.prepareTimeZone();
  final db = AppDatabase();
  try {
    final actions = ReminderActions(ReminderRepository(db.noteDao), scheduler);
    if (response.notificationResponseType ==
        NotificationResponseType.notificationDismissed) {
      await actions.dismissed();
    } else {
      await actions.handle(
        response.actionId,
        payload.noteId,
        setFor: payload.setFor,
      );
    }
  } finally {
    await db.close();
  }
}

/// Reminders rung through Android's alarms and notifications.
class NotificationReminderScheduler implements ReminderScheduler {
  NotificationReminderScheduler([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _channelId = 'reminders';
  static const _channelName = 'Reminders';
  static const _channelDescription =
      'Rings when a note you set a reminder on is due.';

  /// A drawable in the Android project: status bar icons are white glyphs,
  /// and the app's launcher icon would show as a white square.
  static const _icon = 'ic_stat_reminder';

  static Future<void>? _timeZone;

  final FlutterLocalNotificationsPlugin _plugin;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  /// Loads the time zone database and takes the phone's zone as local, once
  /// per isolate.
  Future<void> prepareTimeZone() => _timeZone ??= _loadTimeZone();

  static Future<void> _loadTimeZone() async {
    tz_data.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } on Object catch (error) {
      // Left on UTC, reminders still ring at the right moment; only a repeat
      // shifts by an hour across a daylight saving change.
      debugPrint('Reminders use UTC; the local time zone is unknown: $error');
    }
  }

  /// Readies notifications for the running app. [onOpen] receives the note
  /// id of a notification tapped while the app is running.
  Future<void> initialize({required ValueChanged<String> onOpen}) async {
    await prepareTimeZone();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(_icon),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = ReminderPayload.decode(response.payload);
        if (payload != null &&
            response.notificationResponseType ==
                NotificationResponseType.selectedNotification) {
          onOpen(payload.noteId);
        }
      },
      onDidReceiveBackgroundNotificationResponse: handleReminderAction,
    );
    await _android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
      ),
    );
  }

  /// The note whose notification opened the app, when a tap on one did.
  Future<String?> launchedNoteId() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    final response = details?.notificationResponse;
    if (details == null ||
        !details.didNotificationLaunchApp ||
        response == null ||
        response.actionId != null) {
      return null;
    }
    return ReminderPayload.decode(response.payload)?.noteId;
  }

  @override
  Future<ReminderAccess> access() async {
    final android = _android;
    if (android == null) return ReminderAccess.granted;
    return ReminderAccess(
      notifications: await android.areNotificationsEnabled() ?? false,
      exactAlarms: await android.canScheduleExactNotifications() ?? false,
    );
  }

  @override
  Future<bool> requestNotifications() async {
    await _android?.requestNotificationsPermission();
    return (await access()).notifications;
  }

  @override
  Future<void> requestExactAlarms() async {
    await _android?.requestExactAlarmsPermission();
  }

  @override
  Future<void> openNotificationSettings() async {
    await _android?.openAppNotificationSettings();
  }

  @override
  Future<void> schedule(ScheduledReminder reminder) async {
    // A one-off time that has just passed would be refused.
    if (reminder.repeat == null && !reminder.at.isAfter(DateTime.now())) {
      return;
    }
    await _plugin.zonedSchedule(
      id: reminder.id,
      title: reminder.title,
      body: reminder.body.isEmpty ? null : reminder.body,
      payload: ReminderPayload(reminder.noteId, reminder.setFor).encode(),
      scheduledDate: tz.TZDateTime.from(reminder.at, tz.local),
      androidScheduleMode: reminder.exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: switch (reminder.repeat) {
        null => null,
        ReminderRule.daily => DateTimeComponents.time,
        ReminderRule.weekly => DateTimeComponents.dayOfWeekAndTime,
        ReminderRule.monthly => DateTimeComponents.dayOfMonthAndTime,
        ReminderRule.yearly => DateTimeComponents.dateAndTime,
      },
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          icon: _icon,
          color: AppColors.light.accent,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          styleInformation: BigTextStyleInformation(reminder.body),
          // Swiping away wakes the background handler too, so a repeat whose
          // first ring stood alone is set up without the app being opened.
          dismissIsolate: NotificationDismissedIsolate.background,
          actions: const [
            AndroidNotificationAction(ReminderActions.done, 'Done'),
            AndroidNotificationAction(ReminderActions.snooze, 'Snooze 10 min'),
          ],
        ),
      ),
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<Set<int>> pendingIds() async => {
    for (final request in await _plugin.pendingNotificationRequests())
      request.id,
  };
}
