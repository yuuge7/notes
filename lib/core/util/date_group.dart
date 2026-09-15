import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// One day's worth of notes in the grid.
///
/// Recency is the main way a capture app is navigated, so the day is real
/// structure rather than decoration: it gets a header, a tick on the gutter,
/// and its own section.
@immutable
class DateGroup {
  const DateGroup({required this.label, required this.day});

  /// Uppercase, short, meant for the mono meta face: `TODAY`, `07 SEP`.
  final String label;

  /// Midnight of the group's day, used as the section key.
  final DateTime day;

  @override
  bool operator ==(Object other) =>
      other is DateGroup && other.day == day && other.label == label;

  @override
  int get hashCode => Object.hash(day, label);
}

final _sameYear = DateFormat('dd MMM');
final _otherYear = DateFormat('dd MMM yyyy');

DateTime _midnight(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// Groups [values] into consecutive day sections, preserving order.
///
/// [dateOf] reads the timestamp the grouping is based on, normally
/// `note.updatedAt`. [now] is injectable so tests do not depend on the clock.
List<(DateGroup, List<T>)> groupByDay<T>(
  List<T> values,
  DateTime Function(T) dateOf, {
  DateTime? now,
}) {
  final today = _midnight(now ?? DateTime.now());
  final yesterday = today.subtract(const Duration(days: 1));

  final sections = <(DateGroup, List<T>)>[];
  for (final value in values) {
    final day = _midnight(dateOf(value));
    if (sections.isEmpty || sections.last.$1.day != day) {
      sections.add((
        DateGroup(label: _labelFor(day, today, yesterday), day: day),
        <T>[],
      ));
    }
    sections.last.$2.add(value);
  }
  return sections;
}

String _labelFor(DateTime day, DateTime today, DateTime yesterday) {
  if (day == today) return 'TODAY';
  if (day == yesterday) return 'YESTERDAY';
  final format = day.year == today.year ? _sameYear : _otherYear;
  return format.format(day).toUpperCase();
}
