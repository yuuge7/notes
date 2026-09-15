import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/repository/checklist_repository.dart';
import 'package:notes/data/repository/note_repository.dart';
import 'package:notes/domain/model/checklist_item.dart';
import 'package:notes/domain/model/note_type.dart';

void main() {
  late AppDatabase db;
  late NoteRepository notes;
  late ChecklistRepository lists;
  late String noteId;

  setUp(() async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    notes = NoteRepository(db.noteDao);
    lists = ChecklistRepository(db.noteDao);
    noteId = (await notes.create(
      type: NoteType.checklist,
      title: 'Groceries',
    )).id;
  });

  tearDown(() async {
    await db.close();
  });

  /// The list as (text, indent, checked), in order.
  Future<List<(String, int, bool)>> read() async => [
    for (final item in await lists.items(noteId))
      (item.text, item.indent, item.checked),
  ];

  Future<ChecklistItem> add(String text, {String? after, int? indent}) =>
      lists.add(noteId, afterItemId: after, text: text, indent: indent);

  group('adding', () {
    test('items append to the end of the list', () async {
      await add('Oat milk');
      await add('Sourdough');

      expect(await read(), [('Oat milk', 0, false), ('Sourdough', 0, false)]);
    });

    test('an item added after another lands directly below it', () async {
      final milk = await add('Oat milk');
      await add('Sourdough');

      await add('Eggs', after: milk.id);

      expect((await read()).map((i) => i.$1), [
        'Oat milk',
        'Eggs',
        'Sourdough',
      ]);
    });

    test('a new line inside an indented group stays in the group', () async {
      final bakery = await add('Bakery');
      final sourdough = await add('Sourdough', after: bakery.id, indent: 1);

      await add('Rye', after: sourdough.id);

      expect(await read(), [
        ('Bakery', 0, false),
        ('Sourdough', 1, false),
        ('Rye', 1, false),
      ]);
    });

    test('the first item is never indented', () async {
      await add('Lonely', indent: 1);

      expect(await read(), [('Lonely', 0, false)]);
    });
  });

  group('checking', () {
    test('checking a parent checks its children, and not the next group', () async {
      final bakery = await add('Bakery');
      await add('Sourdough', after: bakery.id, indent: 1);
      await add('Dairy', indent: 0);

      await lists.setChecked(noteId, bakery.id, checked: true);
      expect(await read(), [
        ('Bakery', 0, true),
        ('Sourdough', 1, true),
        ('Dairy', 0, false),
      ]);

      await lists.setChecked(noteId, bakery.id, checked: false);
      expect((await read()).every((i) => !i.$3), isTrue);
    });

    test('checking a child leaves its parent alone', () async {
      final bakery = await add('Bakery');
      final sourdough = await add('Sourdough', after: bakery.id, indent: 1);

      await lists.setChecked(noteId, sourdough.id, checked: true);

      expect(await read(), [('Bakery', 0, false), ('Sourdough', 1, true)]);
    });

    test('uncheck all and delete checked work across the list', () async {
      final a = await add('A');
      final b = await add('B');
      await add('C');
      await lists.setChecked(noteId, a.id, checked: true);
      await lists.setChecked(noteId, b.id, checked: true);

      await lists.uncheckAll(noteId);
      expect((await read()).any((i) => i.$3), isFalse);

      await lists.setChecked(noteId, b.id, checked: true);
      await lists.deleteChecked(noteId);
      expect((await read()).map((i) => i.$1), ['A', 'C']);
    });
  });

  group('indenting and removing', () {
    test('an item indents under the one above and comes back out', () async {
      await add('Bakery');
      final rye = await add('Rye');

      await lists.setIndent(noteId, rye.id, 1);
      expect((await read())[1], ('Rye', 1, false));

      await lists.setIndent(noteId, rye.id, 0);
      expect((await read())[1], ('Rye', 0, false));
    });

    test('the first item refuses an indent', () async {
      final first = await add('First');
      await add('Second');

      await lists.setIndent(noteId, first.id, 1);

      expect((await read()).first, ('First', 0, false));
    });

    test('removing a parent brings its first child out to the top', () async {
      final bakery = await add('Bakery');
      await add('Sourdough', after: bakery.id, indent: 1);

      await lists.remove(noteId, bakery.id);

      expect(await read(), [('Sourdough', 0, false)]);
    });

    test('empty items are cleared out, filled ones stay', () async {
      await add('Keep');
      await add('');
      await add('   ');

      await lists.removeEmpty(noteId);

      expect(await read(), [('Keep', 0, false)]);
    });
  });

  group('merging', () {
    test('backspace at the start joins an item onto the one above', () async {
      await add('Oat ');
      final milk = await add('milk');

      final result = await lists.mergeIntoPrevious(noteId, milk.id);

      expect(await read(), [('Oat milk', 0, false)]);
      expect(result!.cursor, 4);
      expect(result.itemId, (await lists.items(noteId)).single.id);
    });

    test('the first item has nothing above to join', () async {
      final first = await add('First');

      expect(await lists.mergeIntoPrevious(noteId, first.id), isNull);
      expect(await read(), [('First', 0, false)]);
    });

    test('merging skips over checked items to the open item above', () async {
      await add('Tea');
      final done = await add('Done');
      final jam = await add('jam');
      await lists.setChecked(noteId, done.id, checked: true);

      await lists.mergeIntoPrevious(noteId, jam.id);

      expect(await read(), [('Teajam', 0, false), ('Done', 0, true)]);
    });
  });

  group('moving', () {
    test('a parent moves together with its children', () async {
      final bakery = await add('Bakery');
      await add('Sourdough', after: bakery.id, indent: 1);
      final dairy = await add('Dairy', indent: 0);
      final fruit = await add('Fruit');

      await lists.move(
        noteId,
        bakery.id,
        afterItemId: dairy.id,
        beforeItemId: fruit.id,
      );

      expect(await read(), [
        ('Dairy', 0, false),
        ('Bakery', 0, false),
        ('Sourdough', 1, false),
        ('Fruit', 0, false),
      ]);
    });

    test('an item moves to the very top', () async {
      final first = await add('First');
      final last = await add('Last');

      await lists.move(noteId, last.id, beforeItemId: first.id);

      expect((await read()).map((i) => i.$1), ['Last', 'First']);
    });

    test('a child moved to the top comes out to the top level', () async {
      final bakery = await add('Bakery');
      final sourdough = await add('Sourdough', after: bakery.id, indent: 1);

      await lists.move(noteId, sourdough.id, beforeItemId: bakery.id);

      expect(await read(), [('Sourdough', 0, false), ('Bakery', 0, false)]);
    });

    test('dropping a block inside itself changes nothing', () async {
      final bakery = await add('Bakery');
      final sourdough = await add('Sourdough', after: bakery.id, indent: 1);
      await add('Dairy', indent: 0);
      final before = await read();

      await lists.move(noteId, bakery.id, afterItemId: sourdough.id);

      expect(await read(), before);
    });
  });

  group('converting', () {
    test('a text note becomes a checklist line by line', () async {
      final textNote = await notes.create(
        title: 'Shopping',
        body: 'Oat milk\n  Organic\n\n☑ Eggs',
      );

      await lists.toChecklist(textNote.id);

      final converted = (await notes.load(textNote.id))!;
      expect(converted.isChecklist, isTrue);
      expect(converted.body, isEmpty);
      expect(converted.items.map((i) => (i.text, i.indent, i.checked)), [
        ('Oat milk', 0, false),
        ('Organic', 1, false),
        ('Eggs', 0, true),
      ]);
    });

    test('a checklist becomes a text note, keeping indents', () async {
      final bakery = await add('Bakery');
      final sourdough = await add('Sourdough', after: bakery.id, indent: 1);
      await lists.setChecked(noteId, sourdough.id, checked: true);

      await lists.toText(noteId);

      final converted = (await notes.load(noteId))!;
      expect(converted.isChecklist, isFalse);
      expect(converted.body, 'Bakery\n  Sourdough');
      expect(converted.items, isEmpty);
    });
  });

  test('every change to an item marks the note as edited', () async {
    final item = await add('Oat milk');
    final before = (await notes.load(noteId))!.updatedAt;
    await Future<void>.delayed(const Duration(milliseconds: 5));

    await lists.setText(noteId, item.id, 'Oat milk, 2 litres');

    final after = (await notes.load(noteId))!.updatedAt;
    expect(after.isAfter(before), isTrue);
  });
}
