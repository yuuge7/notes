/// The keys a moved note's new sort key must fall between.
///
/// [keys] is one ordered run in display order — the pinned notes, or the
/// unpinned notes — because the two runs sort independently. Moving the item
/// at [from] to position [to] means its new key belongs between the keys that
/// will surround it once it is there; pass them to `SortKey.between`, with an
/// empty string for a null (open) end.
///
/// Returns null when the move changes nothing, so no write is needed.
({String? prev, String? next})? neighboursForMove(
  List<String> keys, {
  required int from,
  required int to,
}) {
  RangeError.checkValidIndex(from, keys, 'from');
  RangeError.checkValueInInterval(to, 0, keys.length - 1, 'to');
  if (from == to) return null;

  final order = [...keys];
  final moved = order.removeAt(from);
  order.insert(to, moved);

  return (
    prev: to == 0 ? null : order[to - 1],
    next: to == order.length - 1 ? null : order[to + 1],
  );
}
