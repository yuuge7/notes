import 'package:flutter_test/flutter_test.dart';
import 'package:notes/core/util/reminder_time.dart';
import 'package:notes/domain/model/reminder_rule.dart';

void main() {
  group('quick picks', () {
    test('later today is 18:00, then 20:00, then not offered', () {
      expect(
        ReminderTime.laterToday(DateTime(2026, 9, 15, 9)),
        DateTime(2026, 9, 15, 18),
      );
      expect(
        ReminderTime.laterToday(DateTime(2026, 9, 15, 17)),
        DateTime(2026, 9, 15, 18),
      );
      expect(
        ReminderTime.laterToday(DateTime(2026, 9, 15, 17, 1)),
        DateTime(2026, 9, 15, 20),
      );
      expect(
        ReminderTime.laterToday(DateTime(2026, 9, 15, 19)),
        DateTime(2026, 9, 15, 20),
      );
      expect(ReminderTime.laterToday(DateTime(2026, 9, 15, 19, 1)), isNull);
    });

    test('tomorrow morning crosses months and years', () {
      expect(
        ReminderTime.tomorrowMorning(DateTime(2026, 12, 31, 23, 30)),
        DateTime(2027, 1, 1, 8),
      );
    });

    test('next week is the coming Monday, or the one after on a Monday', () {
      // 15 September 2026 is a Tuesday.
      expect(
        ReminderTime.nextWeek(DateTime(2026, 9, 15, 10)),
        DateTime(2026, 9, 21, 8),
      );
      expect(
        ReminderTime.nextWeek(DateTime(2026, 9, 20, 22)),
        DateTime(2026, 9, 21, 8),
      );
      expect(
        ReminderTime.nextWeek(DateTime(2026, 9, 21, 7)),
        DateTime(2026, 9, 28, 8),
      );
    });
  });

  group('next ring', () {
    final now = DateTime(2026, 9, 15, 10);

    test('a one-off reminder keeps its time, even once passed', () {
      final past = DateTime(2026, 9, 14, 9);
      expect(ReminderTime.next(past, null, now), past);
    });

    test('a repeating reminder rings at its own time until then', () {
      final coming = DateTime(2026, 9, 20, 9);
      expect(ReminderTime.next(coming, ReminderRule.weekly, now), coming);
    });

    test('daily rings today if the time is still ahead, else tomorrow', () {
      expect(
        ReminderTime.next(DateTime(2026, 9, 1, 11), ReminderRule.daily, now),
        DateTime(2026, 9, 15, 11),
      );
      expect(
        ReminderTime.next(DateTime(2026, 9, 1, 9), ReminderRule.daily, now),
        DateTime(2026, 9, 16, 9),
      );
    });

    test('weekly keeps the weekday', () {
      // 14 September 2026 is a Monday.
      expect(
        ReminderTime.next(DateTime(2026, 9, 14, 9), ReminderRule.weekly, now),
        DateTime(2026, 9, 21, 9),
      );
    });

    test('monthly on the 31st skips months without one', () {
      expect(
        ReminderTime.next(DateTime(2026, 8, 31, 9), ReminderRule.monthly, now),
        DateTime(2026, 10, 31, 9),
      );
    });

    test('yearly on 29 February waits for a leap year', () {
      expect(
        ReminderTime.next(DateTime(2024, 2, 29, 9), ReminderRule.yearly, now),
        DateTime(2028, 2, 29, 9),
      );
    });

    test('a repeat placed from now can land before a far-off first time', () {
      // Today's 09:00 has passed, so the first 15th at 09:00 is October's.
      final november = DateTime(2026, 11, 15, 9);
      expect(
        ReminderTime.repeatsFrom(november, ReminderRule.monthly, now),
        DateTime(2026, 10, 15, 9),
      );
      // Within one period the first ring is the time itself.
      final october = DateTime(2026, 10, 15, 9);
      expect(
        ReminderTime.repeatsFrom(october, ReminderRule.monthly, now),
        october,
      );
    });
  });
}
