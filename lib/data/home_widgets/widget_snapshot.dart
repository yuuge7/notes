import 'dart:convert';

import 'package:notes/core/util/note_description.dart';
import 'package:notes/domain/model/note.dart';
import 'package:notes/domain/model/note_page.dart';

/// Notes the home screen widget holds. It scrolls, but it is a glance, not
/// the grid: the rest are a tap away in the app.
const widgetNoteLimit = 20;

/// Checklist rows a note shows in the widget before counting the rest, as a
/// card in the grid does.
const widgetPreviewItems = 5;

/// A body is cut to this many characters. The widget shows a few lines, and
/// the whole snapshot crosses to Android on every edit.
const widgetBodyLength = 400;

/// The notes of [page] as the home screen widget draws them, in JSON.
///
/// Worked out here rather than on the Android side, so the widget shows a note
/// the way the grid does: pinned first, open items before checked ones, the
/// same words for TalkBack. Reminders are left out, since a reminder can be
/// done or snoozed from its notification without the app running to update
/// the widget.
String encodeWidgetSnapshot(NotePage page) => jsonEncode({
  'version': 1,
  'count': page.total,
  'notes': [
    for (final note in page.notes.take(widgetNoteLimit)) _encodeNote(note),
  ],
});

Map<String, Object?> _encodeNote(Note note) {
  final title = note.title.trim();
  final body = note.isChecklist ? '' : note.body.trim();
  final items = [
    ...note.uncheckedItems,
    ...note.checkedItems,
  ].where((item) => item.text.trim().isNotEmpty).toList();
  final shown = items.take(widgetPreviewItems);
  final images = note.attachments.length;

  return {
    'id': note.id,
    'pigment': note.pigment.name,
    'title': title,
    'body': body.length > widgetBodyLength
        ? '${body.substring(0, widgetBodyLength).trimRight()}…'
        : body,
    'items': [
      for (final item in shown)
        {
          'text': item.text.trim(),
          'checked': item.checked,
          'indent': item.indent,
        },
    ],
    'more': items.length - shown.length,
    'meta': [
      for (final label in note.labels) label.name,
      if (images == 1) '1 image' else if (images > 1) '$images images',
    ].join(' · '),
    'empty': title.isEmpty && body.isEmpty && !note.isChecklist && images == 0,
    'description': describeNote(note),
  };
}
