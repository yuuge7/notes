@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/core/theme/app_colors.dart';
import 'package:notes/core/theme/app_theme.dart';
import 'package:notes/core/theme/tokens.dart';
import 'package:notes/domain/model/checklist_item.dart';
import 'package:notes/domain/model/label.dart';
import 'package:notes/domain/model/note.dart';
import 'package:notes/domain/model/note_type.dart';
import 'package:notes/domain/model/pigment.dart';
import 'package:notes/features/notes/widgets/note_card.dart';

/// The note card in every pigment, in both themes, with the app's own faces.
///
/// Recorded on Windows. Text rasterises differently on other systems, so CI,
/// which runs on Linux, leaves this tag out; run it here with
/// `flutter test --tags golden`, and `--update-goldens` after a deliberate
/// change to the card.
void main() {
  setUpAll(() async {
    for (final (family, asset) in [
      ('Literata', 'assets/fonts/Literata.ttf'),
      ('SchibstedGrotesk', 'assets/fonts/SchibstedGrotesk.ttf'),
      ('MartianMono', 'assets/fonts/MartianMono.ttf'),
      // Tests draw icons as empty boxes unless their font is loaded too.
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      final loader = FontLoader(family)..addFont(rootBundle.load(asset));
      await loader.load();
    }
  });

  // Fixed in a past year, so the card's dates read the same whenever the
  // test runs.
  final at = DateTime(2020, 3, 4, 9, 30);
  final label = Label(id: 'l', name: 'Home', sortKey: 'n', updatedAt: at);

  Note text(Pigment pigment) => Note(
    id: 't-${pigment.name}',
    type: NoteType.text,
    title: pigment.label,
    body:
        'Mihai shows it Thursday at 18:00. Ask whether the boiler was '
        'serviced this year.',
    pigment: pigment,
    sortKey: 'n',
    createdAt: at,
    updatedAt: at,
    labels: [label],
    reminderAt: at,
    reminderDone: true,
  );

  Note list(Pigment pigment) => Note(
    id: 'c-${pigment.name}',
    type: NoteType.checklist,
    title: 'Groceries',
    body: '',
    pigment: pigment,
    sortKey: 'o',
    createdAt: at,
    updatedAt: at,
    items: [
      for (final (index, (item, checked)) in [
        ('Oat milk', false),
        ('Sourdough', false),
        ('Eggs', true),
      ].indexed)
        ChecklistItem(
          id: 'i$index',
          noteId: 'c-${pigment.name}',
          text: item,
          sortKey: 'n$index',
          updatedAt: at,
          checked: checked,
        ),
    ],
  );

  for (final (name, theme) in [
    ('light', AppTheme.light()),
    ('dark', AppTheme.dark()),
  ]) {
    testWidgets('cards in every pigment, $name', (tester) async {
      tester.view.physicalSize = const Size(360, 2240);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          home: Builder(
            builder: (context) => ColoredBox(
              color: Theme.of(context).colors.ground,
              child: Padding(
                padding: const EdgeInsets.all(Gap.lg),
                child: Column(
                  children: [
                    for (final pigment in Pigment.values)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Layout.cardGap),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: NoteCard(
                                note: text(pigment),
                                onTap: () {},
                              ),
                            ),
                            const SizedBox(width: Layout.cardGap),
                            Expanded(
                              child: NoteCard(
                                note: list(pigment),
                                selected: pigment == Pigment.verdigris,
                                onTap: () {},
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('note_cards_$name.png'),
      );
    });
  }
}
