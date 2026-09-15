import 'package:flutter_test/flutter_test.dart';
import 'package:notes/core/util/checklist_rules.dart';
import 'package:notes/core/util/share_text.dart';
import 'package:notes/domain/model/checklist_item.dart';

void main() {
  final at = DateTime(2026, 9, 15);

  ChecklistItem item(
    String text, {
    required String key,
    bool checked = false,
    int indent = 0,
  }) => ChecklistItem(
    id: text,
    noteId: 'note',
    text: text,
    sortKey: key,
    updatedAt: at,
    checked: checked,
    indent: indent,
  );

  group('order', () {
    test('items read in sort-key order, whatever order they arrive in', () {
      final items = [
        item('Third', key: 'p'),
        item('First', key: 'd'),
        item('Second', key: 'h'),
      ];

      expect(ChecklistRules.ordered(items).map((i) => i.text), [
        'First',
        'Second',
        'Third',
      ]);
    });

    test('open and done split the list and keep its order', () {
      final items = [
        item('Eggs', key: 'h', checked: true),
        item('Oat milk', key: 'd'),
        item('Chili oil', key: 'p', checked: true),
        item('Sourdough', key: 'l'),
      ];

      expect(ChecklistRules.open(items).map((i) => i.text), [
        'Oat milk',
        'Sourdough',
      ]);
      expect(ChecklistRules.done(items).map((i) => i.text), [
        'Eggs',
        'Chili oil',
      ]);
    });
  });

  group('children', () {
    final list = [
      item('Bakery', key: 'b'),
      item('Sourdough', key: 'c', indent: 1),
      item('Rye', key: 'd', indent: 1),
      item('Dairy', key: 'e'),
      item('Oat milk', key: 'f', indent: 1),
    ];

    test('a parent owns the indented items directly below it', () {
      expect(ChecklistRules.childrenOf(list, 0).map((i) => i.text), [
        'Sourdough',
        'Rye',
      ]);
      expect(ChecklistRules.childrenOf(list, 3).map((i) => i.text), [
        'Oat milk',
      ]);
    });

    test('a child has no children of its own', () {
      expect(ChecklistRules.childrenOf(list, 1), isEmpty);
    });

    test('a top-level item with nothing indented below it has no children', () {
      final flat = [item('One', key: 'b'), item('Two', key: 'c')];
      expect(ChecklistRules.childrenOf(flat, 0), isEmpty);
    });
  });

  group('indent fixes', () {
    test('the first item can never be indented', () {
      final list = [item('Orphan', key: 'b', indent: 1), item('Next', key: 'c')];

      expect(ChecklistRules.indentFixes(list), {'Orphan': 0});
    });

    test('indents deeper than one level come back to one', () {
      final list = [item('Parent', key: 'b'), item('Deep', key: 'c', indent: 3)];

      expect(ChecklistRules.indentFixes(list), {'Deep': 1});
    });

    test('a list that already reads correctly needs no fixes', () {
      final list = [item('Parent', key: 'b'), item('Child', key: 'c', indent: 1)];

      expect(ChecklistRules.indentFixes(list), isEmpty);
    });
  });

  group('from text', () {
    test('each non-blank line becomes an item', () {
      final entries = ChecklistRules.fromText('Oat milk\n\n  \nSourdough');

      expect(entries.map((e) => e.text), ['Oat milk', 'Sourdough']);
      expect(entries.every((e) => e.indent == 0 && !e.checked), isTrue);
    });

    test('an indented line becomes a child, but never the first one', () {
      final entries = ChecklistRules.fromText(
        '  Loose start\nBakery\n  Sourdough\n\tRye',
      );

      expect(entries.map((e) => (e.text, e.indent)), [
        ('Loose start', 0),
        ('Bakery', 0),
        ('Sourdough', 1),
        ('Rye', 1),
      ]);
    });

    test('bullets and checkbox marks are stripped, and a tick checks the item', () {
      final entries = ChecklistRules.fromText(
        '- Oat milk\n* Eggs\n• Rye\n[ ] Tea\n[x] Coffee\n☐ Jam\n☑ Butter',
      );

      expect(entries.map((e) => e.text), [
        'Oat milk',
        'Eggs',
        'Rye',
        'Tea',
        'Coffee',
        'Jam',
        'Butter',
      ]);
      expect(
        entries.where((e) => e.checked).map((e) => e.text),
        ['Coffee', 'Butter'],
      );
    });

    test('a line that is only a mark is dropped', () {
      expect(ChecklistRules.fromText('☐\n- \nReal item'), hasLength(1));
    });
  });

  group('to text', () {
    test('items become lines in order, children indented, blanks dropped', () {
      final items = [
        item('Sourdough', key: 'c', indent: 1, checked: true),
        item('Bakery', key: 'b'),
        item('  ', key: 'd'),
        item('Dairy', key: 'e'),
      ];

      expect(ChecklistRules.toText(items), 'Bakery\n  Sourdough\nDairy');
    });

    test('a list shared out of the app comes back in with the same items', () {
      final items = [
        item('Bakery', key: 'b'),
        item('Sourdough', key: 'c', indent: 1),
        item('Eggs', key: 'd', checked: true),
      ];
      final shared = shareText(title: '', items: items);

      final back = ChecklistRules.fromText(shared);

      expect(back.map((e) => (e.text, e.indent, e.checked)), [
        ('Bakery', 0, false),
        ('Sourdough', 1, false),
        ('Eggs', 0, true),
      ]);
    });
  });
}
