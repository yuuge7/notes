import 'package:flutter_test/flutter_test.dart';
import 'package:notes/core/util/date_group.dart';

void main() {
  final now = DateTime(2026, 9, 14, 15, 30);

  List<(DateGroup, List<DateTime>)> group(List<DateTime> values) =>
      groupByDay(values, (value) => value, now: now);

  test('labels today and yesterday by name', () {
    final sections = group([
      DateTime(2026, 9, 14, 9),
      DateTime(2026, 9, 13, 23, 59),
    ]);
    expect(sections.map((s) => s.$1.label), ['TODAY', 'YESTERDAY']);
  });

  test('labels older days this year without the year', () {
    final sections = group([DateTime(2026, 9, 7, 12)]);
    expect(sections.single.$1.label, '07 SEP');
  });

  test('labels days from another year with the year', () {
    final sections = group([DateTime(2025, 12, 31, 8)]);
    expect(sections.single.$1.label, '31 DEC 2025');
  });

  test('keeps consecutive notes from one day in one section', () {
    final sections = group([
      DateTime(2026, 9, 14, 14),
      DateTime(2026, 9, 14, 8),
      DateTime(2026, 9, 12, 20),
      DateTime(2026, 9, 12, 7),
    ]);
    expect(sections, hasLength(2));
    expect(sections.first.$2, hasLength(2));
    expect(sections.last.$2, hasLength(2));
  });

  test('preserves input order instead of re-sorting', () {
    // Manual order can put an older capture above a newer one. The grid
    // follows that order, so a day may appear twice rather than notes moving.
    final sections = group([
      DateTime(2026, 9, 12, 7),
      DateTime(2026, 9, 14, 8),
      DateTime(2026, 9, 12, 20),
    ]);
    expect(sections.map((s) => s.$1.label), ['12 SEP', 'TODAY', '12 SEP']);
  });

  test('empty input yields no sections', () {
    expect(group(const []), isEmpty);
  });
}
