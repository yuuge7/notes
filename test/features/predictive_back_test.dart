import 'dart:async';
import 'dart:io';

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
import 'package:notes/data/seed.dart';

import '../support/fake_home_widgets.dart';
import '../support/fake_phone_system.dart';
import '../support/fake_reminder_scheduler.dart';

/// Android's predictive back: dragging back from a pushed page shows the page
/// below before letting go.
void main() {
  late AppDatabase db;
  late Directory media;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    media = Directory.systemTemp.createTempSync('notes_back_media_');
  });

  tearDown(() async {
    await db.close();
    media.deleteSync(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> gesture(String method, [Map<String, Object?>? arguments]) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            'flutter/backgesture',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall(method, arguments),
            ),
            (_) {},
          );

  testWidgets('dragging back from settings shows the page below', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => seedIfEmpty(db.noteDao));
    final router = buildRouter();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          mediaRootProvider.overrideWith((ref) async => media),
          cacheRootProvider.overrideWith((ref) async => media),
          reminderSchedulerProvider.overrideWithValue(FakeReminderScheduler()),
          phoneSystemProvider.overrideWithValue(FakePhoneSystem()),
          homeWidgetsProvider.overrideWithValue(FakeHomeWidgets()),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await settle(tester);
    unawaited(router.push('/settings'));
    await settle(tester);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Take a note'), findsNothing);

    final resting = tester.getRect(find.text('Settings'));

    await gesture('startBackGesture', {
      'touchOffset': [5.0, 300.0],
      'progress': 0.0,
      'swipeEdge': 0,
    });
    await tester.pump();
    await gesture('updateBackGestureProgress', {
      'x': 100.0,
      'y': 300.0,
      'progress': 0.35,
      'swipeEdge': 0,
    });
    await tester.pump(const Duration(milliseconds: 100));

    // Settings draws smaller as it is dragged, with the grid showing below.
    expect(tester.getRect(find.text('Settings')), isNot(resting));
    expect(find.text('Take a note'), findsOneWidget);

    await gesture('commitBackGesture');
    await settle(tester);
    expect(find.text('Settings'), findsNothing);
    expect(find.text('Take a note'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
