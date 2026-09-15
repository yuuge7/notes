import 'package:flutter_test/flutter_test.dart';
import 'package:notes/core/util/share_text.dart';
import 'package:notes/domain/model/checklist_item.dart';

void main() {
  final at = DateTime(2026, 9, 15);

  ChecklistItem item(String text, {bool checked = false, int indent = 0}) =>
      ChecklistItem(
        id: text,
        noteId: 'note',
        text: text,
        sortKey: text,
        updatedAt: at,
        checked: checked,
        indent: indent,
      );

  test('a text note is its title, a blank line, and its body', () {
    expect(
      shareText(title: 'Bike', body: 'Rear brake pads are down to the metal.'),
      'Bike\n\nRear brake pads are down to the metal.',
    );
  });

  test('a note without a title is just its body', () {
    expect(shareText(title: '  ', body: 'Call the plumber'), 'Call the plumber');
  });

  test('a note without a body is just its title', () {
    expect(shareText(title: 'Dentist', body: '\n'), 'Dentist');
  });

  test('a checklist keeps item state and indentation', () {
    expect(
      shareText(
        title: 'Groceries',
        items: [
          item('Oat milk'),
          item('Eggs', checked: true),
          item('Free-range', indent: 1),
        ],
      ),
      'Groceries\n\n☐ Oat milk\n☑ Eggs\n  ☐ Free-range',
    );
  });

  test('empty checklist items are left out', () {
    expect(
      shareText(title: 'List', items: [item(''), item('Keep'), item('  ')]),
      'List\n\n☐ Keep',
    );
  });

  test('a checklist ignores the body field', () {
    expect(
      shareText(title: 'List', body: 'stale text', items: [item('Only item')]),
      'List\n\n☐ Only item',
    );
  });

  test('nothing to send gives an empty string', () {
    expect(shareText(title: '', body: '   '), isEmpty);
    expect(shareText(title: '', items: [item('')]), isEmpty);
  });
}
