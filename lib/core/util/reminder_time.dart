import 'package:notes/domain/model/reminder_rule.dart';

/// The times a reminder can be set for with one tap, and when a repeating
/// reminder rings next.
abstract final class ReminderTime {
  static const morningHour = 8;
  static const eveningHour = 18;

  /// Where the evening pick moves once 18:00 is too close to be "later".
  static const lateHour = 20;

  /// How far ahead "later today" has to be to be worth offering.
  static const _lead = Duration(hours: 1);

  /// How long Snooze on a notification puts a reminder off.
  static const snooze = Duration(minutes: 10);

  /// This evening at 18:00, or 20:00 once 18:00 is under an hour away. Null
  /// once 20:00 is under an hour away too, when "later today" would mean
  /// almost now.
  static DateTime? laterToday(DateTime now) {
    for (final hour in const [eveningHour, lateHour]) {
      final at = DateTime(now.year, now.month, now.day, hour);
      if (!now.isAfter(at.subtract(_lead))) return at;
    }
    return null;
  }

  /// Tomorrow at 08:00.
  static DateTime tomorrowMorning(DateTime now) =>
      DateTime(now.year, now.month, now.day + 1, morningHour);

  /// The coming Monday at 08:00; on a Monday, the Monday after.
  static DateTime nextWeek(DateTime now) {
    final days = (DateTime.monday - now.weekday) % DateTime.daysPerWeek;
    return DateTime(
      now.year,
      now.month,
      now.day + (days == 0 ? DateTime.daysPerWeek : days),
      morningHour,
    );
  }

  /// When a reminder set for [at] rings next, as seen at [now].
  ///
  /// A one-off reminder rings at [at], even after that has passed. A
  /// repeating one rings at [at] until then, and afterwards as [repeatsFrom]
  /// finds.
  static DateTime next(DateTime at, ReminderRule? rule, DateTime now) {
    if (rule == null || !at.isBefore(now)) return at;
    return repeatsFrom(at, rule, now);
  }

  /// The first time at or after [now] that matches [at] under [rule].
  ///
  /// This mirrors how Android places a repeating notification, when it is
  /// scheduled and again each time it rings, so the time the app shows is
  /// the time the phone rings. From today at [at]'s time of day it steps a
  /// day at a time until the date matches: any day for daily, the weekday for
  /// weekly, the day of the month for monthly, the month and day for yearly.
  /// A monthly reminder on the 31st therefore skips shorter months, and a
  /// yearly one on 29 February rings in leap years only.
  static DateTime repeatsFrom(DateTime at, ReminderRule rule, DateTime now) {
    bool matches(DateTime day) => switch (rule) {
      ReminderRule.daily => true,
      ReminderRule.weekly => day.weekday == at.weekday,
      ReminderRule.monthly => day.day == at.day,
      ReminderRule.yearly => day.month == at.month && day.day == at.day,
    };
    DateTime dayAfterToday(int days) => DateTime(
      now.year,
      now.month,
      now.day + days,
      at.hour,
      at.minute,
      at.second,
    );

    var days = 0;
    var candidate = dayAfterToday(days);
    while (candidate.isBefore(now) || !matches(candidate)) {
      candidate = dayAfterToday(++days);
    }
    return candidate;
  }
}
