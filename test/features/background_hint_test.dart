import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/core/router/router.dart';
import 'package:notes/core/theme/app_theme.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/data/repository/settings_repository.dart';
import 'package:notes/data/seed.dart';
import 'package:notes/domain/service/reminder_scheduler.dart';

import '../support/fake_phone_system.dart';
import '../support/fake_reminder_scheduler.dart';

/// The one-time hint for phones whose makers stop apps in the background.
void main() {
  late AppDatabase db;
  late FakeReminderScheduler scheduler;
  late FakePhoneSystem phone;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    scheduler = FakeReminderScheduler();
    phone = FakePhoneSystem();
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

  Future<void> pumpReminders(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => seedIfEmpty(db.noteDao));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          reminderSchedulerProvider.overrideWithValue(scheduler),
          phoneSystemProvider.overrideWithValue(phone),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: buildRouter(initialLocation: '/reminders'),
        ),
      ),
    );
    await settle(tester);
  }

  const hint = 'MAY NOT RING WHILE CLOSED';

  testWidgets('a Xiaomi phone is told once, and settings open from it', (
    tester,
  ) async {
    phone.maker = 'Xiaomi';
    await pumpReminders(tester);

    expect(find.text(hint), findsOneWidget);
    expect(find.textContaining('Xiaomi phones can stop Notes'), findsOneWidget);

    await tester.tap(find.text('Open settings'));
    await settle(tester);

    expect(phone.backgroundSettingsOpened, 1);
    expect(find.text(hint), findsNothing);
    expect(
      await tester.runAsync(
        () => SettingsRepository(db.preferenceDao).backgroundHintDone(),
      ),
      isTrue,
    );
  });

  testWidgets('dismissing it keeps it away', (tester) async {
    phone.maker = 'samsung';
    await pumpReminders(tester);

    await tester.tap(find.text('Dismiss'));
    await settle(tester);
    expect(find.text(hint), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await pumpReminders(tester);
    expect(find.text(hint), findsNothing);
    expect(phone.backgroundSettingsOpened, 0);
  });

  testWidgets('a phone not known for it hears nothing', (tester) async {
    phone.maker = 'Google';
    await pumpReminders(tester);

    expect(find.text(hint), findsNothing);
  });

  testWidgets('it waits while Android itself keeps reminders from ringing', (
    tester,
  ) async {
    phone.maker = 'Xiaomi';
    scheduler.currentAccess = const ReminderAccess(
      notifications: false,
      exactAlarms: true,
    );
    await pumpReminders(tester);

    expect(find.text('NOTIFICATIONS ARE OFF'), findsOneWidget);
    expect(find.text(hint), findsNothing);
  });
}
