import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:notes/domain/model/reminder_rule.dart';

/// How reminder times read: in mono capitals, the day first, the way the
/// grid's day headers do.
abstract final class ReminderFormat {
  static final _weekdayDayMonth = DateFormat('EEE dd MMM');
  static final _dayMonth = DateFormat('dd MMM');
  static final _dayMonthYear = DateFormat('dd MMM yyyy');

  /// The clock time, in the phone's 12- or 24-hour format.
  static String time(BuildContext context, DateTime at) =>
      MaterialLocalizations.of(context)
          .formatTimeOfDay(
            TimeOfDay.fromDateTime(at),
            alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
          )
          .toUpperCase();

  /// `TODAY`, `TOMORROW`, `YESTERDAY`, `MON 21 SEP` this year, and
  /// `21 SEP 2027` beyond it.
  static String day(DateTime at, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final days = _daysBetween(today, at);
    if (days == 0) return 'TODAY';
    if (days == 1) return 'TOMORROW';
    if (days == -1) return 'YESTERDAY';
    final format = at.year == today.year ? _weekdayDayMonth : _dayMonthYear;
    return format.format(at).toUpperCase();
  }

  /// `TOMORROW 8:00 AM`, followed by `· WEEKLY` when it repeats.
  static String full(
    BuildContext context,
    DateTime at,
    ReminderRule? rule, {
    DateTime? now,
  }) {
    final when = '${day(at, now: now)} ${time(context, at)}';
    return rule == null ? when : '$when · ${rule.label.toUpperCase()}';
  }

  /// As short as a card allows: the time today, `TOMORROW`, `YESTERDAY`,
  /// then the day and month.
  static String compact(BuildContext context, DateTime at, {DateTime? now}) {
    final today = now ?? DateTime.now();
    return switch (_daysBetween(today, at)) {
      0 => time(context, at),
      1 => 'TOMORROW',
      -1 => 'YESTERDAY',
      _ => _dayMonth.format(at).toUpperCase(),
    };
  }

  /// Calendar days from [from] to [to], unaffected by daylight saving.
  static int _daysBetween(DateTime from, DateTime to) => DateTime.utc(
    to.year,
    to.month,
    to.day,
  ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
}
