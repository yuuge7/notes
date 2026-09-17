import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes/core/util/note_description.dart';
import 'package:notes/data/home_widgets/widget_snapshot.dart';
import 'package:notes/domain/model/attachment.dart';
import 'package:notes/domain/model/checklist_item.dart';
import 'package:notes/domain/model/label.dart';
import 'package:notes/domain/model/note.dart';
import 'package:notes/domain/model/note_page.dart';
import 'package:notes/domain/model/note_type.dart';
import 'package:notes/domain/model/pigment.dart';

/// What the home screen widget is handed: the notes as the grid shows them,
/// cut to what fits a glance.
void main() {
  final at = DateTime(2026, 9, 14, 9, 12);

  Note note(
    String id, {
    String title = '',
    String body = '',
    Pigment pigment = Pigment.graphite,
    bool pinned = false,
    NoteType type = NoteType.text,
    List<ChecklistItem> items = const [],
    List<Label> labels = const [],
    int images = 0,
  }) => Note(
    id: id,
    type: type,
    title: title,
    body: body,
    pigment: pigment,
    sortKey: 'n',
    createdAt: at,
    updatedAt: at,
    pinned: pinned,
    items: items,
    labels: labels,
    attachments: [
      for (var i = 0; i < images; i++)
        Attachment(
          id: '$id-image-$i',
          noteId: id,
          relPath: 'a$i.jpg',
          thumbPath: 't$i.jpg',
          width: 800,
          height: 600,
          bytes: 1000,
          mime: 'image/jpeg',
          sortKey: 'n$i',
          createdAt: at,
        ),
    ],
  );

  ChecklistItem item(String text, {bool checked = false, int indent = 0}) =>
      ChecklistItem(
        id: text,
        noteId: 'list',
        text: text,
        sortKey: text,
        updatedAt: at,
        checked: checked,
        indent: indent,
      );

  Map<String, Object?> decode(List<Note> notes, {int? total}) => jsonDecode(
    encodeWidgetSnapshot(NotePage(notes: notes, total: total ?? notes.length)),
  ) as Map<String, Object?>;

  List<Map<String, Object?>> notesOf(Map<String, Object?> snapshot) => [
    for (final n in snapshot['notes']! as List) n as Map<String, Object?>,
  ];

  test('keeps the grid order and counts the whole shelf', () {
    final snapshot = decode([
      note('a', title: 'Flat viewing', pinned: true),
      note('b', title: 'Groceries'),
    ], total: 12);

    expect(snapshot['version'], 1);
    expect(snapshot['count'], 12);
    expect([for (final n in notesOf(snapshot)) n['id']], ['a', 'b']);
  });

  test('holds at most $widgetNoteLimit notes', () {
    final snapshot = decode([
      for (var i = 0; i < 25; i++) note('n$i', title: 'Note $i'),
    ]);

    expect(notesOf(snapshot), hasLength(widgetNoteLimit));
    expect(notesOf(snapshot).last['id'], 'n19');
    expect(snapshot['count'], 25);
  });

  test('a list shows open items first and counts what it leaves out', () {
    final list = note(
      'list',
      title: 'Groceries',
      type: NoteType.checklist,
      body: 'left over from when it was a text note',
      items: [
        item('Eggs', checked: true),
        item('Oat milk'),
        item('  '),
        item('Sourdough', indent: 1),
        item('Coffee'),
        item('Rice'),
        item('Lemons'),
      ],
    );

    final shown = notesOf(decode([list])).single;

    expect(shown['body'], '');
    expect(shown['items'], [
      {'text': 'Oat milk', 'checked': false, 'indent': 0},
      {'text': 'Sourdough', 'checked': false, 'indent': 1},
      {'text': 'Coffee', 'checked': false, 'indent': 0},
      {'text': 'Rice', 'checked': false, 'indent': 0},
      {'text': 'Lemons', 'checked': false, 'indent': 0},
    ]);
    // Eggs, checked, is the one left out; the blank item is not counted.
    expect(shown['more'], 1);
  });

  test('a long body is cut, and marked as cut', () {
    final body = List.filled(100, 'Ten chars.').join(' ');

    final shown = notesOf(decode([note('long', body: body)])).single;

    // Cut at the limit, less a trailing space, plus the ellipsis.
    expect(
      (shown['body']! as String).length,
      inInclusiveRange(widgetBodyLength - 1, widgetBodyLength + 1),
    );
    expect(shown['body'], endsWith('…'));
  });

  test('labels and images go on the meta line', () {
    final shown = notesOf(
      decode([
        note(
          'tiles',
          title: 'Tiles for the bathroom',
          labels: [Label(id: 'h', name: 'Home', sortKey: 'n', updatedAt: at)],
          images: 3,
        ),
        note('one', images: 1),
      ]),
    );

    expect(shown[0]['meta'], 'Home · 3 images');
    expect(shown[1]['meta'], '1 image');
  });

  test('only a note with nothing at all is empty', () {
    final shown = notesOf(
      decode([
        note('blank'),
        note('photo', images: 1),
        note('list', type: NoteType.checklist),
      ]),
    );

    expect([for (final n in shown) n['empty']], [true, false, false]);
  });

  test('TalkBack hears the note as it does on its card', () {
    final pinned = note(
      'a',
      title: 'Flat viewing',
      body: 'Ask about the boiler.',
      pigment: Pigment.verdigris,
      pinned: true,
    );

    final shown = notesOf(decode([pinned])).single;

    expect(shown['description'], describeNote(pinned));
    expect(
      shown['description'],
      'Pinned. Flat viewing. Ask about the boiler. Verdigris',
    );
    expect(shown['pigment'], 'verdigris');
  });
}
