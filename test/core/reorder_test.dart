import 'package:flutter_test/flutter_test.dart';
import 'package:notes/core/util/reorder.dart';
import 'package:notes/core/util/sort_key.dart';

void main() {
  /// [count] ascending keys, built the way the app builds them.
  List<String> run(int count) {
    final keys = <String>[SortKey.first];
    while (keys.length < count) {
      keys.add(SortKey.after(keys.last));
    }
    return keys;
  }

  /// Applies a move exactly as the app does — one new key for the moved item,
  /// every other key untouched — and returns the original indices in their
  /// new sorted order.
  List<int> orderAfterMove(List<String> keys, int from, int to) {
    final bounds = neighboursForMove(keys, from: from, to: to);
    final updated = [...keys];
    if (bounds != null) {
      updated[from] = SortKey.between(bounds.prev ?? '', bounds.next ?? '');
    }
    return List.generate(keys.length, (i) => i)
      ..sort((a, b) => updated[a].compareTo(updated[b]));
  }

  test('moving down lands after the item it was dropped on', () {
    expect(orderAfterMove(run(4), 0, 2), [1, 2, 0, 3]);
  });

  test('moving up lands before the item it was dropped on', () {
    expect(orderAfterMove(run(4), 3, 1), [0, 3, 1, 2]);
  });

  test('moving to the start leaves the lower end open', () {
    final keys = run(3);
    final bounds = neighboursForMove(keys, from: 2, to: 0)!;

    expect(bounds.prev, isNull);
    expect(bounds.next, keys[0]);
  });

  test('moving to the end leaves the upper end open', () {
    final keys = run(3);
    final bounds = neighboursForMove(keys, from: 0, to: 2)!;

    expect(bounds.prev, keys[2]);
    expect(bounds.next, isNull);
  });

  test('dropping an item on its own place changes nothing', () {
    expect(neighboursForMove(run(3), from: 1, to: 1), isNull);
  });

  test('every move in a run of six lands exactly where it was dropped', () {
    final keys = run(6);
    for (var from = 0; from < keys.length; from++) {
      for (var to = 0; to < keys.length; to++) {
        final expected = List.generate(keys.length, (i) => i)
          ..removeAt(from)
          ..insert(to, from);
        expect(
          orderAfterMove(keys, from, to),
          expected,
          reason: 'moving $from to $to',
        );
      }
    }
  });

  test('rejects positions outside the run', () {
    expect(
      () => neighboursForMove(run(3), from: 0, to: 3),
      throwsRangeError,
    );
    expect(
      () => neighboursForMove(run(3), from: 3, to: 0),
      throwsRangeError,
    );
  });
}
