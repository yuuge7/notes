import 'package:notes/domain/service/reminder_scheduler.dart';

/// A scheduler that keeps its alarms in memory, standing in for Android.
class FakeReminderScheduler implements ReminderScheduler {
  ReminderAccess currentAccess = ReminderAccess.granted;

  /// What [requestNotifications] grants.
  bool grantOnRequest = true;

  /// Waiting notifications, by id.
  final pending = <int, ScheduledReminder>{};

  /// Every call made, in order, as short strings such as `schedule 3`.
  final log = <String>[];

  int exactAlarmRequests = 0;
  int settingsOpened = 0;

  @override
  Future<ReminderAccess> access() async => currentAccess;

  @override
  Future<bool> requestNotifications() async {
    log.add('request notifications');
    if (grantOnRequest) {
      currentAccess = ReminderAccess(
        notifications: true,
        exactAlarms: currentAccess.exactAlarms,
      );
    }
    return currentAccess.notifications;
  }

  @override
  Future<void> requestExactAlarms() async => exactAlarmRequests++;

  @override
  Future<void> openNotificationSettings() async => settingsOpened++;

  @override
  Future<void> schedule(ScheduledReminder reminder) async {
    log.add('schedule ${reminder.id}');
    pending[reminder.id] = reminder;
  }

  @override
  Future<void> cancel(int id) async {
    log.add('cancel $id');
    pending.remove(id);
  }

  @override
  Future<Set<int>> pendingIds() async => {...pending.keys};
}
