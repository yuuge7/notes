import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/core/theme/app_theme.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/features/notes/notes_screen.dart';

/// Share from the editor, checked at the platform boundary: what share_plus
/// actually hands to Android's share sheet.
void main() {
  late AppDatabase db;
  final shared = <MethodCall>[];

  const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    shared.clear();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      shareChannel,
      (call) async {
        shared.add(call);
        return 'dev.fluttercommunity.plus/share/unavailable';
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        shareChannel,
        null,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const NotesScreen(),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> shareFromMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('More'));
    await settle(tester);
    await tester.tap(find.text('Share'));
    await settle(tester);
  }

  Map<Object?, Object?> onlyShare() {
    expect(shared, hasLength(1));
    expect(shared.single.method, 'share');
    return shared.single.arguments as Map<Object?, Object?>;
  }

  testWidgets('sharing a text note sends its title and body', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Bike'));
    await settle(tester);
    await shareFromMenu(tester);

    final args = onlyShare();
    expect(args['text'], 'Bike\n\nRear brake pads are down to the metal.');
    expect(args['subject'], 'Bike');
  });

  testWidgets('sharing a checklist sends each item with its state', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Groceries'));
    await settle(tester);
    await shareFromMenu(tester);

    expect(
      onlyShare()['text'],
      'Groceries\n\n'
      '☐ Oat milk\n'
      '☐ Sourdough\n'
      '☑ Eggs\n'
      '☐ Coffee beans — the dark roast\n'
      '☑ Chili oil',
    );
  });

  testWidgets('sharing uses the text on the page, including an edit just made', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Bike'));
    await settle(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Rear brake pads are down to the metal.'),
      'Front pads too.',
    );
    // Share straight away, without leaving the editor.
    await shareFromMenu(tester);

    expect(onlyShare()['text'], 'Bike\n\nFront pads too.');
    await settle(tester);
  });
}
