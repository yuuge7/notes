import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/core/router/router.dart';
import 'package:notes/core/theme/app_theme.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/features/notes/notes_screen.dart';

/// From Android 16, back goes straight to the system unless the app has told
/// it that it will handle back itself. Flutter says so with
/// `SystemNavigator.setFrameworkHandlesBack`. If an open drawer or a selection
/// does not claim back, one press leaves the app instead of closing the drawer
/// or clearing the selection.
void main() {
  late AppDatabase db;
  final claims = <bool>[];

  bool claimsBack() => claims.isNotEmpty && claims.last;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    claims.clear();
  });

  tearDown(() async {
    await db.close();
  });

  /// Records every back claim the app sends and marks the app resumed: the
  /// app only reports back handling once it knows it is running, and a test
  /// binding starts with no lifecycle state at all.
  void listenForClaims(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
          claims.add(call.arguments as bool);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpGrid(WidgetTester tester) async {
    listenForClaims(tester);
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

  /// The setup the device runs: the real routes behind a go_router.
  Future<void> pumpRouterAt(WidgetTester tester, String location) async {
    listenForClaims(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: buildRouter(initialLocation: location),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> pressBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await settle(tester);
  }

  testWidgets('with nothing open, the grid leaves back to the system', (
    tester,
  ) async {
    await pumpGrid(tester);

    expect(claimsBack(), isFalse);
  });

  testWidgets('an open drawer claims back, and back closes only the drawer', (
    tester,
  ) async {
    await pumpGrid(tester);

    await tester.tap(find.byTooltip('Open menu'));
    await settle(tester);
    expect(find.text('KEPT ON THIS DEVICE'), findsOneWidget);
    expect(claimsBack(), isTrue);

    await pressBack(tester);

    expect(find.text('KEPT ON THIS DEVICE'), findsNothing);
    expect(find.byTooltip('Open menu'), findsOneWidget);
    expect(claimsBack(), isFalse);
  });

  testWidgets('a selection claims back, and back clears it', (tester) async {
    await pumpGrid(tester);

    await tester.longPress(find.text('Bike'));
    await tester.pump();
    expect(find.byTooltip('Clear selection'), findsOneWidget);
    expect(claimsBack(), isTrue);

    await pressBack(tester);

    expect(find.byTooltip('Clear selection'), findsNothing);
    expect(find.byTooltip('Open menu'), findsOneWidget);
    expect(claimsBack(), isFalse);
  });

  testWidgets(
    'in the archive, back closes the drawer, then returns to the grid',
    (tester) async {
      await pumpRouterAt(tester, '/archive');
      expect(find.text('Nothing archived'), findsOneWidget);
      // A secondary shelf always claims back: back returns to the grid.
      expect(claimsBack(), isTrue);

      await tester.tap(find.byTooltip('Open menu'));
      await settle(tester);
      expect(find.text('KEPT ON THIS DEVICE'), findsOneWidget);

      await pressBack(tester);
      expect(find.text('KEPT ON THIS DEVICE'), findsNothing);
      expect(find.text('Nothing archived'), findsOneWidget);

      await pressBack(tester);
      expect(find.text('Nothing archived'), findsNothing);
      expect(find.text('8 NOTES'), findsOneWidget);
      expect(claimsBack(), isFalse);
    },
  );
}
