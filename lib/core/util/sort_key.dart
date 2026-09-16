/// Fractional indexing over the alphabet `a`-`z`.
///
/// A note's position is a string that sorts lexicographically. Inserting
/// between two neighbours means generating a string that sits between their
/// keys, so a drag-reorder writes exactly one row and never renumbers the
/// table. Keys grow one character at a time under repeated subdivision, which
/// is fine: reordering the same gap 20 times costs 20 characters.
abstract final class SortKey {
  /// Character before `a`, used as the lower bound of an open range.
  static const int _below = 96;

  /// Character after `z`, used as the upper bound of an open range.
  static const int _above = 123;

  /// The key for the first item in an empty list.
  static const String first = 'n';

  /// A key that sorts between [prev] and [next].
  ///
  /// Pass an empty string for an open end: `between('', 'm')` yields a key
  /// before `m`, `between('m', '')` one after it.
  static String between(String prev, String next) {
    assert(
      prev.isEmpty || next.isEmpty || prev.compareTo(next) < 0,
      'prev must sort before next, got "$prev" and "$next"',
    );

    var p = 0;
    var n = 0;
    var pos = 0;

    // Walk past the shared prefix.
    while (p == n) {
      p = pos < prev.length ? prev.codeUnitAt(pos) : _below;
      n = pos < next.length ? next.codeUnitAt(pos) : _above;
      pos++;
    }

    var result = prev.substring(0, pos - 1);

    if (p == _below) {
      // prev ran out. Copy leading 'a's from next so we stay above prev.
      while (n == 97) {
        n = pos < next.length ? next.codeUnitAt(pos++) : _above;
        result += 'a';
      }
      if (n == 98) {
        result += 'a';
        n = _above;
      }
    } else if (p + 1 == n) {
      // The two keys are adjacent. Extend prev instead of splitting.
      result += String.fromCharCode(p);
      n = _above;
      while ((p = pos < prev.length ? prev.codeUnitAt(pos++) : _below) == 122) {
        result += 'z';
      }
    }

    // Round up. Rounding down can produce a key ending in 'a', and no key
    // sorts between such a key and its prefix, so the next insert above it
    // would land in the wrong place.
    return result + String.fromCharCode((p + n + 1) ~/ 2);
  }

  /// [count] keys in ascending order, all between [after] and [before], with
  /// an empty string for an open end.
  ///
  /// Each key halves the gap left to it, so the keys stay short however many
  /// are placed: a thousand fit in three characters. Placing them one after
  /// another would add a character every few keys.
  static List<String> spread(
    int count, {
    String after = '',
    String before = '',
  }) {
    final keys = List.filled(count, '');
    void fill(int low, int high, String prev, String next) {
      if (low > high) return;
      final middle = (low + high) ~/ 2;
      final key = between(prev, next);
      keys[middle] = key;
      fill(low, middle - 1, prev, key);
      fill(middle + 1, high, key, next);
    }

    fill(0, count - 1, after, before);
    return keys;
  }

  /// A key that sorts before [key].
  static String before(String key) => between('', key);

  /// A key that sorts after [key].
  static String after(String key) => between(key, '');
}
