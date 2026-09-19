import 'dart:convert';

import 'package:notes/core/util/note_description.dart';
import 'package:notes/data/db/note_dao.dart';
import 'package:notes/data/device/home_widgets.dart';
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

/// Notes named in a feed's preview, where a widget's settings offer it.
const widgetPreviewNotes = 3;

/// Every set of notes a widget can show, as the home screen widgets draw
/// them, in JSON.
///
/// Worked out here rather than on the Android side, so the widget shows a note
/// the way the grid does: pinned first, open items before checked ones, the
/// same words for TalkBack. Each widget shows one feed, chosen as it is placed;
/// a note on several feeds is written once and named by id. Reminders are left
/// out, since a reminder can be done or snoozed from its notification without
/// the app running to update the widget.
String encodeWidgetSnapshot(WidgetShelves shelves) {
  final feeds = [
    (
      feed: const AllFeed(),
      name: AllFeed.name,
      title: 'Notes',
      page: shelves.all,
    ),
    (
      feed: const PinnedFeed(),
      name: PinnedFeed.name,
      title: 'Pinned',
      page: shelves.pinned,
    ),
    for (final (:label, :page) in shelves.labels)
      (
        feed: LabelFeed(label.id),
        name: label.name,
        title: label.name,
        page: page,
      ),
  ];
  final notes = <String, Map<String, Object?>>{};
  for (final shelf in feeds) {
    for (final note in shelf.page.notes.take(widgetNoteLimit)) {
      notes[note.id] ??= _encodeNote(note);
    }
  }
  return jsonEncode({
    'version': 2,
    'feeds': [
      for (final (:feed, :name, :title, :page) in feeds)
        _encodeFeed(feed, name, title, page),
    ],
    'notes': notes,
  });
}

Map<String, Object?> _encodeFeed(
  WidgetFeed feed,
  String name,
  String title,
  NotePage page,
) {
  final shown = page.notes.take(widgetNoteLimit);
  return {
    'feed': feed.key,
    'name': name,
    'title': title,
    'count': page.total,
    'notes': [for (final note in shown) note.id],
    'preview': shown.take(widgetPreviewNotes).map(_headline).join(' · '),
    'empty': switch (feed) {
      AllFeed() => 'Tap + to take a note',
      PinnedFeed() => 'Tap + to take a pinned note',
      LabelFeed() => 'Tap + to take a note wearing “$title”',
    },
  };
}

/// A note in a few words: its title, or else the first thing it holds, in the
/// order its card shows it.
String _headline(Note note) {
  final images = note.attachments.length;
  return [
        note.title,
        if (note.isChecklist)
          for (final item in [...note.uncheckedItems, ...note.checkedItems])
            item.text
        else
          ...note.body.split('\n'),
        if (images > 0) imageCount(images),
      ]
      .map((text) => text.trim())
      .firstWhere((text) => text.isNotEmpty, orElse: () => 'Empty note');
}

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
      if (images > 0) imageCount(images),
    ].join(' · '),
    'empty': title.isEmpty && body.isEmpty && !note.isChecklist && images == 0,
    'description': describeNote(note),
  };
}
