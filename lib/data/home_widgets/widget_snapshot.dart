import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:notes/core/util/checklist_rules.dart';
import 'package:notes/core/util/note_description.dart';
import 'package:notes/data/db/note_dao.dart';
import 'package:notes/data/device/home_widgets.dart';
import 'package:notes/domain/model/checklist_item.dart';
import 'package:notes/domain/model/note.dart';
import 'package:notes/domain/model/note_page.dart';
import 'package:notes/domain/model/settings.dart';

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

/// Notes a note widget's settings offer: the grid's first, pinned ones
/// first. Any note goes on the home screen from its own menu too.
const widgetChoiceLimit = 50;

/// Items a note widget lists before counting the rest. A list longer than
/// this is past what a widget is for.
const widgetPageItems = 100;

/// A note widget's body is cut to this many characters.
const widgetPageBodyLength = 2000;

/// Every set of notes a widget can show, as the home screen widgets draw
/// them, in JSON.
///
/// Worked out here rather than on the Android side, so the widget shows a note
/// the way the grid does: pinned first, open items before checked ones, the
/// same words for TalkBack. Each notes widget shows one feed, chosen as it is
/// placed; a note on several feeds is written once and named by id. Reminders
/// are left out, since a reminder can be done or snoozed from its notification
/// without the app running to update the widget.
///
/// A note widget shows one note whole, as its page does, with the checked
/// items where [checkedItems] puts them in the editor.
String encodeWidgetSnapshot(
  WidgetShelves shelves, {
  CheckedItems checkedItems = CheckedItems.folded,
}) {
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
    'version': 3,
    'feeds': [
      for (final (:feed, :name, :title, :page) in feeds)
        _encodeFeed(feed, name, title, page),
    ],
    'notes': notes,
    'choices': [for (final note in shelves.choices) _encodeChoice(note)],
    // Null for a note deleted since its widget was set to it, which the
    // widget says; a note missing here is one the app has not loaded yet.
    'pages': {
      for (final MapEntry(key: id, value: note) in shelves.pages.entries)
        id: note == null ? null : _encodePage(note, checkedItems),
    },
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
String _headline(Note note) => _words(note).firstOrNull ?? 'Empty note';

/// Everything a note holds that has words, in the order its card shows it.
Iterable<String> _words(Note note) {
  final images = note.attachments.length;
  return [
    note.title,
    if (note.isChecklist)
      for (final item in [...note.uncheckedItems, ...note.checkedItems])
        item.text
    else
      ...note.body.split('\n'),
    if (images > 0) imageCount(images),
  ].map((text) => text.trim()).where((text) => text.isNotEmpty);
}

/// A note as a note widget's settings offer it: its headline, over what
/// follows it.
Map<String, Object?> _encodeChoice(Note note) {
  final words = _words(note);
  return {
    'id': note.id,
    'name': words.firstOrNull ?? 'Empty note',
    'preview': words.skip(1).take(widgetPreviewNotes).join(' · '),
  };
}

/// A note as a note widget shows it: the whole of it, or near enough, with
/// each item named, so a tick on the home screen reaches it.
///
/// Open items come first and the checked ones after them under their count,
/// or all in order when [checkedItems] leaves them in place, as in the
/// editor.
Map<String, Object?> _encodePage(Note note, CheckedItems checkedItems) {
  final title = note.title.trim();
  final body = note.isChecklist ? '' : note.body.trim();
  final items = [
    for (final item in ChecklistRules.ordered(note.items))
      if (item.text.trim().isNotEmpty) item,
  ];
  final atBottom = checkedItems.atBottom;
  final open = [
    for (final item in items)
      if (!atBottom || !item.checked) item,
  ];
  final done = [
    for (final item in items)
      if (atBottom && item.checked) item,
  ];
  final shownOpen = open.take(widgetPageItems).toList();
  final shownDone = done.take(widgetPageItems - shownOpen.length).toList();
  final checked = items.where((item) => item.checked).length;
  final progress = note.isChecklist && items.isNotEmpty
      ? '$checked of ${items.length} done'
      : '';
  final images = note.attachments.length;

  Map<String, Object?> encodeItem(ChecklistItem item, {required int indent}) =>
      {
        'id': item.id,
        'text': item.text.trim(),
        'checked': item.checked,
        'indent': indent,
      };

  return {
    'id': note.id,
    'pigment': note.pigment.name,
    'checklist': note.isChecklist,
    'title': title,
    'meta': [
      if (progress.isNotEmpty) progress,
      if (images > 0) imageCount(images),
    ].join(' · '),
    // The heading for TalkBack, which has no title to read on an untitled
    // note.
    'label': [
      if (title.isNotEmpty)
        title
      else if (note.isChecklist)
        'Untitled list'
      else
        'Untitled note',
      if (progress.isNotEmpty) progress,
    ].join('. '),
    'body': body.length > widgetPageBodyLength
        ? '${body.substring(0, widgetPageBodyLength).trimRight()}…'
        : body,
    'items': [
      for (final item in shownOpen) encodeItem(item, indent: item.indent),
    ],
    // Out of their group, as in the editor, which draws them unindented.
    'done': [for (final item in shownDone) encodeItem(item, indent: 0)],
    'doneCount': switch (done.length) {
      0 => '',
      1 => '1 checked item',
      final count => '$count checked items',
    },
    'folded': checkedItems == CheckedItems.folded,
    // Counted apart, so checked items past the limit stay folded with the
    // rest, and a list whose open items fill the widget still has its count.
    'more': open.length - shownOpen.length,
    'moreDone': done.length - shownDone.length,
    'empty': switch ((note.isChecklist, images)) {
      (true, _) => 'Nothing on this list yet',
      (false, 0) => 'Nothing written here yet',
      (false, _) => 'Only images here. Tap to see them',
    },
  };
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
