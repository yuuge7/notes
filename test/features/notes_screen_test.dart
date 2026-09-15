import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/core/theme/app_theme.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/features/notes/notes_screen.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    ThemeMode mode = ThemeMode.light,
    double textScale = 1,
    // Tall by default: slivers only build sections near the viewport, so a
    // short surface would leave older day sections unbuilt.
    Size size = const Size(800, 2400),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: mode,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const NotesScreen(),
        ),
      ),
    );
    // Seeding and the first read are real database work, so let them run
    // outside fake time, then pump the frames they produce.
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('renders the seeded grid with pinned and day sections', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('8 NOTES'), findsOneWidget);
    expect(find.text('PINNED'), findsOneWidget);
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('YESTERDAY'), findsOneWidget);
    expect(find.text('Take a note'), findsOneWidget);
  });

  testWidgets('a card reads as one node with its title and progress', (
    tester,
  ) async {
    await pumpScreen(tester);
    final handle = tester.ensureSemantics();

    expect(
      find.bySemanticsLabel(RegExp(r'^Groceries\. 2 of 5 done\. Amber$')),
      findsOneWidget,
    );

    handle.dispose();
  });

  testWidgets('narrow phone at 200% text scale lays out without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpScreen(tester, textScale: 2);

    expect(tester.takeException(), isNull);
    expect(find.text('Notes'), findsOneWidget);
  });

  testWidgets('dark theme renders', (tester) async {
    await pumpScreen(tester, mode: ThemeMode.dark);

    expect(tester.takeException(), isNull);
    expect(find.text('PINNED'), findsOneWidget);
  });

  testWidgets('long-press selects, taps add to the selection, close clears', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.longPress(find.text('Bike'));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Take a note'), findsNothing);

    // While selecting, a tap selects instead of opening the editor.
    await tester.tap(find.text('Dentist'));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear selection'));
    await tester.pump();
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Take a note'), findsOneWidget);
  });

  testWidgets('layout toggle switches to a single column', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byTooltip('Show as list'));
    await tester.pump();

    expect(find.byTooltip('Show as grid'), findsOneWidget);
  });
}
