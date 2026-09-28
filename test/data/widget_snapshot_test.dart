import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes/core/util/note_description.dart';
import 'package:notes/data/db/note_dao.dart';
import 'package:notes/data/home_widgets/widget_snapshot.dart';
import 'package:notes/domain/model/attachment.dart';
import 'package:notes/domain/model/checklist_item.dart';
import 'package:notes/domain/model/label.dart';
import 'package:notes/domain/model/note.dart';
import 'package:notes/domain/model/note_page.dart';
import 'package:notes/domain/model/note_type.dart';
import 'package:notes/domain/model/pigment.dart';
import 'package:notes/domain/model/settings.dart';

/// What the home screen widgets are handed: every feed a widget can show, and
/// the notes on them as the grid shows them, cut to what fits a glance.
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

  NotePage page(List<Note> notes, {int? total}) =>
      NotePage(notes: notes, total: total ?? notes.length);

  Label label(String id, String name) =>
      Label(id: id, name: name, sortKey: id, updatedAt: at);

  Map<String, Object?> encode(WidgetShelves shelves) =>
      jsonDecode(encodeWidgetSnapshot(shelves)) as Map<String, Object?>;

  /// The grid alone: no pinned notes, no labels.
  Map<String, Object?> decode(List<Note> notes, {int? total}) => encode((
    all: page(notes, total: total),
    pinned: page(const []),
    labels: const [],
    choices: const [],
    pages: const {},
  ));

  List<Map<String, Object?>> feedsOf(Map<String, Object?> snapshot) => [
    for (final feed in snapshot['feeds']! as List) feed as Map<String, Object?>,
  ];

  Map<String, Object?> feed(Map<String, Object?> snapshot, String key) =>
      feedsOf(snapshot).firstWhere((feed) => feed['feed'] == key);

  /// The notes of the grid's feed, in its order.
  List<Map<String, Object?>> notesOf(Map<String, Object?> snapshot) {
    final notes = snapshot['notes']! as Map<String, Object?>;
    return [
      for (final id in feed(snapshot, 'all')['notes']! as List)
        notes[id]! as Map<String, Object?>,
    ];
  }

  test('keeps the grid order and counts the whole shelf', () {
    final snapshot = decode([
      note('a', title: 'Flat viewing', pinned: true),
      note('b', title: 'Groceries'),
    ], total: 12);

    expect(snapshot['version'], 3);
    expect(feed(snapshot, 'all')['count'], 12);
    expect([for (final n in notesOf(snapshot)) n['id']], ['a', 'b']);
  });

  test('holds at most $widgetNoteLimit notes', () {
    final snapshot = decode([
      for (var i = 0; i < 25; i++) note('n$i', title: 'Note $i'),
    ]);

    expect(notesOf(snapshot), hasLength(widgetNoteLimit));
    expect(notesOf(snapshot).last['id'], 'n19');
    expect(feed(snapshot, 'all')['count'], 25);
    expect(snapshot['notes']! as Map, hasLength(widgetNoteLimit));
  });

  group('feeds', () {
    final home = label('h', 'Home');
    final admin = label('a', 'Admin');
    final flat = note('flat', title: 'Flat viewing', pinned: true);
    final groceries = note('groceries', title: 'Groceries', labels: [home]);
    final shelves = (
      all: page([flat, groceries], total: 9),
      pinned: page([flat], total: 1),
      labels: [
        (label: home, page: page([flat, groceries])),
        (label: admin, page: page(const [])),
      ],
      choices: const <Note>[],
      pages: const <String, Note?>{},
    );

    test('the grid, the pinned notes, then each label in order', () {
      final feeds = feedsOf(encode(shelves));

      expect(
        [
          for (final feed in feeds)
            (feed['feed'], feed['name'], feed['title'], feed['count']),
        ],
        [
          ('all', 'All notes', 'Notes', 9),
          ('pinned', 'Pinned notes', 'Pinned', 1),
          ('label:h', 'Home', 'Home', 2),
          ('label:a', 'Admin', 'Admin', 0),
        ],
      );
      expect(
        [for (final feed in feeds) feed['notes']],
        [
          ['flat', 'groceries'],
          ['flat'],
          ['flat', 'groceries'],
          <String>[],
        ],
      );
    });

    test('a note on several feeds is written once', () {
      final notes = encode(shelves)['notes']! as Map<String, Object?>;

      expect(notes.keys, ['flat', 'groceries']);
    });

    test('each invites a note that lands on it when empty', () {
      final snapshot = encode(shelves);

      expect(feed(snapshot, 'all')['empty'], 'Tap + to take a note');
      expect(feed(snapshot, 'pinned')['empty'], 'Tap + to take a pinned note');
      expect(
        feed(snapshot, 'label:a')['empty'],
        'Tap + to take a note wearing “Admin”',
      );
    });

    test('previews its first notes in a few words', () {
      final snapshot = decode([
        note('titled', title: '  Flat viewing '),
        note('body', body: '\n  Call the landlord\nabout the boiler'),
        note(
          'list',
          type: NoteType.checklist,
          items: [item('Eggs', checked: true), item('Oat milk')],
        ),
        note('fourth', title: 'Left out'),
      ]);

      expect(
        feed(snapshot, 'all')['preview'],
        'Flat viewing · Call the landlord · Oat milk',
      );
      expect(feed(snapshot, 'pinned')['preview'], '');
    });

    test('a note with no words previews as what it holds', () {
      final snapshot = decode([note('photos', images: 2), note('blank')]);

      expect(feed(snapshot, 'all')['preview'], '2 images · Empty note');
    });
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
          labels: [label('h', 'Home')],
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

  group('note widgets', () {
    ChecklistItem listItem(
      String key,
      String text, {
      bool checked = false,
      int indent = 0,
    }) => ChecklistItem(
      id: 'item-$key',
      noteId: 'list',
      text: text,
      sortKey: key,
      updatedAt: at,
      checked: checked,
      indent: indent,
    );

    final groceries = note(
      'list',
      title: 'Groceries',
      type: NoteType.checklist,
      pigment: Pigment.moss,
      items: [
        listItem('a', 'Oat milk'),
        listItem('b', 'Eggs', checked: true),
        listItem('c', 'Sourdough'),
        listItem('d', 'Seeded', indent: 1),
        listItem('e', ' '),
        listItem('f', 'Lemons', checked: true),
      ],
    );

    Map<String, Object?> encodePages(
      Map<String, Note?> pages, {
      List<Note> choices = const [],
      CheckedItems checkedItems = CheckedItems.folded,
    }) => jsonDecode(
      encodeWidgetSnapshot((
        all: page(const []),
        pinned: page(const []),
        labels: const [],
        choices: choices,
        pages: pages,
      ), checkedItems: checkedItems),
    ) as Map<String, Object?>;

    Map<String, Object?> pageOf(
      Note note, {
      CheckedItems checkedItems = CheckedItems.folded,
    }) =>
        (encodePages({note.id: note}, checkedItems: checkedItems)['pages']!
                as Map<String, Object?>)[note.id]!
            as Map<String, Object?>;

    List<String> texts(Object? items) => [
      for (final item in items! as List) (item as Map)['text'] as String,
    ];

    test("offer the grid's notes by headline, over what follows", () {
      final snapshot = encodePages(
        const {},
        choices: [
          groceries,
          note('flat', title: 'Flat viewing', body: 'Thursday\nAsk about it'),
          note('blank'),
        ],
      );

      expect(snapshot['choices'], [
        {
          'id': 'list',
          'name': 'Groceries',
          'preview': 'Oat milk · Sourdough · Seeded',
        },
        {
          'id': 'flat',
          'name': 'Flat viewing',
          'preview': 'Thursday · Ask about it',
        },
        {'id': 'blank', 'name': 'Empty note', 'preview': ''},
      ]);
    });

    test('show every item by id, open ones first, checked below', () {
      final shown = pageOf(groceries);

      expect(shown['checklist'], isTrue);
      expect(shown['title'], 'Groceries');
      expect(shown['pigment'], 'moss');
      expect(shown['items'], [
        {'id': 'item-a', 'text': 'Oat milk', 'checked': false, 'indent': 0},
        {'id': 'item-c', 'text': 'Sourdough', 'checked': false, 'indent': 0},
        {'id': 'item-d', 'text': 'Seeded', 'checked': false, 'indent': 1},
      ]);
      expect(texts(shown['done']), ['Eggs', 'Lemons']);
      expect(shown['doneCount'], '2 checked items');
      expect(shown['folded'], isTrue);
      // The blank item is not counted.
      expect(shown['meta'], '2 of 5 done');
      expect(shown['more'], 0);
      expect(shown['moreDone'], 0);
    });

    test('fold the checked items only where the setting does', () {
      final atBottom = pageOf(groceries, checkedItems: CheckedItems.shown);
      final inPlace = pageOf(groceries, checkedItems: CheckedItems.inPlace);

      expect(atBottom['folded'], isFalse);
      expect(texts(atBottom['done']), ['Eggs', 'Lemons']);
      expect(texts(inPlace['items']), [
        'Oat milk',
        'Eggs',
        'Sourdough',
        'Seeded',
        'Lemons',
      ]);
      expect(inPlace['done'], isEmpty);
      expect(inPlace['doneCount'], '');
    });

    test('a checked child leaves its group, as in the editor', () {
      final list = note(
        'list',
        type: NoteType.checklist,
        items: [
          listItem('a', 'Bread'),
          listItem('b', 'Seeded', checked: true, indent: 1),
        ],
      );

      expect((pageOf(list)['done']! as List).single, {
        'id': 'item-b',
        'text': 'Seeded',
        'checked': true,
        'indent': 0,
      });
    });

    test('a long list counts what it leaves out', () {
      final list = note(
        'list',
        type: NoteType.checklist,
        items: [
          for (var i = 0; i < widgetPageItems + 5; i++)
            listItem(i.toString().padLeft(3, '0'), 'Item $i', checked: i.isOdd),
        ],
      );

      final shown = pageOf(list);

      expect(
        (shown['items']! as List).length + (shown['done']! as List).length,
        widgetPageItems,
      );
      // 53 open items all fit; the checked ones fill the rest, less 5.
      expect(shown['more'], 0);
      expect(shown['moreDone'], 5);
      expect(shown['doneCount'], '52 checked items');
    });

    test('open items filling the widget keep the checked count', () {
      final list = note(
        'list',
        type: NoteType.checklist,
        items: [
          for (var i = 0; i < widgetPageItems + 3; i++)
            listItem(i.toString().padLeft(3, '0'), 'Item $i'),
          listItem('zzz', 'Done', checked: true),
        ],
      );

      final shown = pageOf(list);

      expect(shown['items'], hasLength(widgetPageItems));
      expect(shown['more'], 3);
      expect(shown['done'], isEmpty);
      expect(shown['moreDone'], 1);
      expect(shown['doneCount'], '1 checked item');
    });

    test('a text note shows its text, cut when long', () {
      final long = note('long', body: List.filled(300, 'Ten chars.').join(' '));
      final flat = note('flat', title: 'Flat viewing', body: ' Thursday ');

      expect(pageOf(flat)['body'], 'Thursday');
      expect(pageOf(flat)['checklist'], isFalse);
      expect(pageOf(flat)['items'], isEmpty);
      expect(
        (pageOf(long)['body']! as String).length,
        inInclusiveRange(widgetPageBodyLength - 1, widgetPageBodyLength + 1),
      );
    });

    test('say what an empty note holds', () {
      expect(
        pageOf(note('list', type: NoteType.checklist))['empty'],
        'Nothing on this list yet',
      );
      expect(pageOf(note('blank'))['empty'], 'Nothing written here yet');
      expect(
        pageOf(note('photo', images: 2))['empty'],
        'Only images here. Tap to see them',
      );
      expect(pageOf(note('photo', images: 2))['meta'], '2 images');
    });

    test('TalkBack hears the heading, untitled or not', () {
      expect(pageOf(groceries)['label'], 'Groceries. 2 of 5 done');
      expect(
        pageOf(note('list', type: NoteType.checklist))['label'],
        'Untitled list',
      );
      expect(pageOf(note('blank'))['label'], 'Untitled note');
    });

    test('name a note deleted since as gone', () {
      final pages =
          encodePages({'gone': null, 'list': groceries})['pages']!
              as Map<String, Object?>;

      expect(pages.keys, ['gone', 'list']);
      expect(pages['gone'], isNull);
    });
  });
}
