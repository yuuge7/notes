import 'package:notes/domain/model/checklist_item.dart';

/// A note as plain text for another app: the title, a blank line, then the
/// body or the checklist.
///
/// Checklist items keep their state as ☐ and ☑ so a shared list still reads
/// as a list wherever it lands, and indented items are indented with two
/// spaces. Empty items are left out. Returns an empty string when there is
/// nothing to send.
String shareText({
  required String title,
  String body = '',
  List<ChecklistItem> items = const [],
}) {
  final heading = title.trim();

  final content = items.isNotEmpty
      ? [
          for (final item in items)
            if (item.text.trim().isNotEmpty)
              '${'  ' * item.indent}${item.checked ? '☑' : '☐'} ${item.text.trim()}',
        ].join('\n')
      : body.trim();

  return [
    if (heading.isNotEmpty) heading,
    if (content.isNotEmpty) content,
  ].join('\n\n');
}
