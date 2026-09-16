import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes/core/util/sort_key.dart';

void main() {
  group('SortKey.between', () {
    test('open range yields the first key', () {
      expect(SortKey.between('', ''), SortKey.first);
    });

    test('before and after bracket a key', () {
      const key = 'm';
      expect(SortKey.before(key).compareTo(key), lessThan(0));
      expect(SortKey.after(key).compareTo(key), greaterThan(0));
    });

    test('adjacent keys still get a key between them', () {
      final key = SortKey.between('a', 'b');
      expect(key.compareTo('a'), greaterThan(0));
      expect(key.compareTo('b'), lessThan(0));
    });

    test('keys never end in the lowest character', () {
      // A key ending in "a" would leave no room below it.
      var low = '';
      for (var i = 0; i < 50; i++) {
        low = SortKey.before(low.isEmpty ? SortKey.first : low);
        expect(low.endsWith('a'), isFalse, reason: 'key "$low"');
      }
    });

    test('repeatedly prepending keeps order', () {
      final keys = <String>[SortKey.first];
      for (var i = 0; i < 200; i++) {
        keys.insert(0, SortKey.before(keys.first));
      }
      final sorted = [...keys]..sort();
      expect(keys, sorted);
      expect(keys.toSet().length, keys.length);
    });

    test('random inserts between neighbours keep a strict order', () {
      final random = Random(7);
      final keys = <String>[SortKey.first];
      for (var i = 0; i < 500; i++) {
        final slot = random.nextInt(keys.length + 1);
        final prev = slot == 0 ? '' : keys[slot - 1];
        final next = slot == keys.length ? '' : keys[slot];
        final key = SortKey.between(prev, next);
        if (prev.isNotEmpty) expect(key.compareTo(prev), greaterThan(0));
        if (next.isNotEmpty) expect(key.compareTo(next), lessThan(0));
        keys.insert(slot, key);
      }
      final sorted = [...keys]..sort();
      expect(keys, sorted);
    });
  });
  group('SortKey.spread', () {
    test('gives ascending keys inside the bounds', () {
      for (final (after, before) in [
        ('', ''),
        ('', 'g'),
        ('m', ''),
        ('c', 'd'),
      ]) {
        final keys = SortKey.spread(40, after: after, before: before);
        expect(keys, hasLength(40));
        for (var i = 0; i < keys.length; i++) {
          if (i > 0) expect(keys[i - 1].compareTo(keys[i]), lessThan(0));
          if (after.isNotEmpty) {
            expect(keys[i].compareTo(after), greaterThan(0));
          }
          if (before.isNotEmpty) {
            expect(keys[i].compareTo(before), lessThan(0));
          }
          expect(keys[i].endsWith('a'), isFalse);
        }
      }
    });

    test('stays short for many keys', () {
      final keys = SortKey.spread(5000, before: 'g');
      expect(keys.map((key) => key.length).reduce(max), lessThanOrEqualTo(5));
    });

    test('gives nothing for no keys', () {
      expect(SortKey.spread(0), isEmpty);
    });
  });
}
