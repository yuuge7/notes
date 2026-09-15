import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/core/theme/app_theme.dart';
import 'package:notes/domain/model/checklist_item.dart';
import 'package:notes/domain/model/label.dart';
import 'package:notes/domain/model/note.dart';
import 'package:notes/domain/model/note_type.dart';
import 'package:notes/domain/model/pigment.dart';
import 'package:notes/features/notes/widgets/note_card.dart';

/// What TalkBack reads for a card. Each card is one node, so this label is
/// the whole of what a screen-reader user hears about the note.
void main() {
  final at = DateTime(2026, 9, 14, 9, 12);

  Note note({
    String title = '',
    String body = '',
    Pigment pigment = Pigment.graphite,
    bool pinned = false,
    NoteType type = NoteType.text,
    List<ChecklistItem> items = const [],
    List<Label> labels = const [],
  }) {
    return Note(
      id: 'note',
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
    );
  }

  ChecklistItem item(String text, {bool checked = false}) => ChecklistItem(
    id: text,
    noteId: 'note',
    text: text,
    sortKey: text,
    updatedAt: at,
    checked: checked,
  );

  Label label(String name) =>
      Label(id: name, name: name, sortKey: name, updatedAt: at);

  Future<String> spokenLabel(WidgetTester tester, Note value) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: NoteCard(note: value, onTap: () {}),
            ),
          ),
        ),
      ),
    );
    final spoken = tester.getSemantics(find.byType(NoteCard)).label;
    handle.dispose();
    return spoken;
  }

  testWidgets('a body ending in a full stop is not read with a doubled stop', (
    tester,
  ) async {
    final spoken = await spokenLabel(
      tester,
      note(
        title: 'Bike',
        body: 'Rear brake pads are down to the metal.',
        pigment: Pigment.moss,
      ),
    );

    expect(spoken, 'Bike. Rear brake pads are down to the metal. Moss');
  });

  testWidgets('a note without a title says so', (tester) async {
    final spoken = await spokenLabel(
      tester,
      note(body: 'Sitting down at a fixed hour is the work!'),
    );

    expect(spoken, 'Untitled note. Sitting down at a fixed hour is the work');
  });

  testWidgets('a pinned checklist reads its progress and labels', (
    tester,
  ) async {
    final spoken = await spokenLabel(
      tester,
      note(
        title: 'Groceries',
        type: NoteType.checklist,
        pinned: true,
        pigment: Pigment.amber,
        items: [
          item('Oat milk'),
          item('Eggs', checked: true),
          item('Chili oil', checked: true),
        ],
        labels: [label('Home'), label('Weekly')],
      ),
    );

    expect(
      spoken,
      'Pinned. Groceries. 2 of 3 done. Labels: Home, Weekly. Amber',
    );
  });

  testWidgets('a note with no colour does not announce one', (tester) async {
    final spoken = await spokenLabel(
      tester,
      note(title: 'Dentist', body: 'Tuesday 14:30'),
    );

    expect(spoken, 'Dentist. Tuesday 14:30');
  });
}
