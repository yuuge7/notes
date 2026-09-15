import 'package:notes/domain/model/checklist_item.dart';

/// One entry parsed from text on its way into a checklist.
typedef ChecklistEntry = ({String text, int indent, bool checked});

/// How checklist items relate to each other, kept apart from the database and
/// the widgets so the rules can be tested on their own.
///
/// Items live in one sequence ordered by sort key. An item with indent 1 is
/// the child of the nearest top-level item above it, and a parent with its
/// children forms a block that moves and checks as one.
abstract final class ChecklistRules {
  /// [items] in display order.
  static List<ChecklistItem> ordered(Iterable<ChecklistItem> items) =>
      [...items]..sort((a, b) => a.sortKey.compareTo(b.sortKey));

  /// Unchecked items in order: the part of the list still being worked on.
  static List<ChecklistItem> open(Iterable<ChecklistItem> items) => [
    for (final item in ordered(items))
      if (!item.checked) item,
  ];

  /// Checked items in order.
  static List<ChecklistItem> done(Iterable<ChecklistItem> items) => [
    for (final item in ordered(items))
      if (item.checked) item,
  ];

  /// The children of the item at [index] in [ordered]: the indented items
  /// directly below it, up to the next top-level item. A child has none.
  static List<ChecklistItem> childrenOf(List<ChecklistItem> ordered, int index) {
    if (ordered[index].indent != 0) return const [];
    return [
      for (var i = index + 1; i < ordered.length && ordered[i].indent == 1; i++)
        ordered[i],
    ];
  }

  /// Indents that must change so [ordered] reads correctly: only 0 or 1, and
  /// never 1 for the first item, which has no parent above it.
  static Map<String, int> indentFixes(List<ChecklistItem> ordered) {
    final fixes = <String, int>{};
    for (var i = 0; i < ordered.length; i++) {
      final item = ordered[i];
      final wanted = i == 0 ? 0 : item.indent.clamp(0, 1);
      if (wanted != item.indent) fixes[item.id] = wanted;
    }
    return fixes;
  }

  static final _mark = RegExp(r'^(☐|☑|\[ \]|\[x\]|[-*•])\s*', caseSensitive: false);

  /// Lines of text as checklist entries.
  ///
  /// Blank lines are dropped. A line indented by a tab or two spaces becomes a
  /// child, except the first entry, which has no parent. Bullets and checkbox
  /// marks — including the ☐ and ☑ this app shares — are stripped, and ☑ or
  /// `[x]` brings the item in already checked.
  static List<ChecklistEntry> fromText(String text) {
    final entries = <ChecklistEntry>[];
    for (final raw in text.split('\n')) {
      final indented = raw.startsWith('\t') || raw.startsWith('  ');
      var line = raw.trim();
      var checked = false;

      final mark = _mark.firstMatch(line);
      if (mark != null) {
        final symbol = mark.group(1)!.toLowerCase();
        checked = symbol == '☑' || symbol == '[x]';
        line = line.substring(mark.end).trim();
      }
      if (line.isEmpty) continue;

      entries.add((
        text: line,
        indent: indented && entries.isNotEmpty ? 1 : 0,
        checked: checked,
      ));
    }
    return entries;
  }

  /// A checklist as the body of a text note: one line per item, children
  /// indented by two spaces. Checked state does not survive the trip, and
  /// empty items are left out.
  static String toText(Iterable<ChecklistItem> items) => [
    for (final item in ordered(items))
      if (item.text.trim().isNotEmpty) '${'  ' * item.indent}${item.text.trim()}',
  ].join('\n');
}
