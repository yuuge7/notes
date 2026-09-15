import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/core/router/router.dart';
import 'package:notes/core/theme/app_theme.dart';
import 'package:notes/core/util/reminder_time.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/db/note_dao.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/data/repository/note_repository.dart';
import 'package:notes/data/repository/reminder_repository.dart';
import 'package:notes/domain/model/note.dart';
import 'package:notes/domain/model/note_type.dart';
import 'package:notes/domain/model/pigment.dart';
import 'package:notes/domain/model/reminder_rule.dart';
import 'package:notes/domain/service/reminder_scheduler.dart';
import 'package:notes/features/reminders/reminders_screen.dart';

import '../support/fake_reminder_scheduler.dart';

/// Reminders set from the editor, and the page that lists them.
void main() {
  late AppDatabase db;
  late FakeReminderScheduler scheduler;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    scheduler = FakeReminderScheduler();
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

  Future<void> pumpApp(WidgetTester tester, {String at = '/'}) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          reminderSchedulerProvider.overrideWithValue(scheduler),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: buildRouter(initialLocation: at),
        ),
      ),
    );
    await settle(tester);
  }

  Future<String> noteIdOf(String title) async => (await db.noteDao.loadShelf(
    Shelf.active,
  )).firstWhere((note) => note.title == title).id;

  testWidgets('a time picked in the editor is set and shown on the page', (
    tester,
  ) async {
    scheduler.currentAccess = const ReminderAccess(
      notifications: false,
      exactAlarms: true,
    );
    await pumpApp(tester);

    await tester.tap(find.text('Bike'));
    await settle(tester);
    await tester.tap(find.byTooltip('Reminder'));
    await settle(tester);
    await tester.tap(find.text('Tomorrow morning'));
    await settle(tester);

    final bike = (await tester.runAsync<Note?>(
      () async => db.noteDao.loadNote(await noteIdOf('Bike')),
    ))!;
    expect(bike.reminderAt, ReminderTime.tomorrowMorning(DateTime.now()));
    expect(bike.reminderRule, isNull);
    expect(find.text('Tomorrow morning'), findsNothing);
    expect(find.textContaining('TOMORROW 8:00 AM'), findsOneWidget);
    // The first reminder asks for permission to notify.
    expect(scheduler.log, contains('request notifications'));
  });

  testWidgets('a new repeat applies at once, and removing can be undone', (
    tester,
  ) async {
    await pumpApp(tester);
    final bikeId = (await tester.runAsync(() => noteIdOf('Bike')))!;
    final tomorrow = ReminderTime.tomorrowMorning(DateTime.now());
    await tester.runAsync(
      () => ReminderRepository(db.noteDao).set(bikeId, tomorrow),
    );

    await tester.tap(find.text('Bike'));
    await settle(tester);
    await tester.tap(find.textContaining('TOMORROW 8:00 AM'));
    await settle(tester);

    await tester.tap(find.text('Weekly'));
    await settle(tester);
    Future<Note> loadBike() async =>
        (await tester.runAsync<Note?>(() => db.noteDao.loadNote(bikeId)))!;
    var bike = await loadBike();
    expect(bike.reminderRule, ReminderRule.weekly);
    expect(find.text('Tomorrow morning'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await settle(tester);
    bike = await loadBike();
    expect(bike.hasReminder, isFalse);
    expect(find.text('Reminder removed'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await settle(tester);
    bike = await loadBike();
    expect(bike.reminderAt, tomorrow);
    expect(bike.reminderRule, ReminderRule.weekly);
  });

  testWidgets('the sheet sees exact alarms allowed on return from settings', (
    tester,
  ) async {
    scheduler.currentAccess = const ReminderAccess(
      notifications: true,
      exactAlarms: false,
    );
    await pumpApp(tester);
    await tester.tap(find.text('Bike'));
    await settle(tester);
    await tester.tap(find.byTooltip('Reminder'));
    await settle(tester);
    expect(find.text('Allow exact alarms'), findsOneWidget);

    // Allowed in settings while the app was in the background. Android steps
    // through every state on the way out and back, and the listener expects
    // each step.
    scheduler.currentAccess = ReminderAccess.granted;
    const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ].forEach(tester.binding.handleAppLifecycleStateChanged);
    await settle(tester);

    expect(find.text('Allow exact alarms'), findsNothing);
    expect(find.text('Tomorrow morning'), findsOneWidget);
  });

  testWidgets('the reminders page groups overdue, today, and upcoming', (
    tester,
  ) async {
    final now = DateTime.now();
    final notes = NoteRepository(db.noteDao);
    final reminders = ReminderRepository(db.noteDao);
    Future<String> add(String title) async =>
        (await notes.create(title: title)).id;

    await reminders.set(
      await add('Call the bank'),
      now.subtract(const Duration(hours: 2)),
    );
    await reminders.set(
      await add('Water the fern'),
      DateTime(now.year, now.month, now.day, 23, 59),
    );
    await reminders.set(
      await add('Renew passport'),
      now.add(const Duration(days: 3)),
    );
    final finished = await add('Finished');
    await reminders.set(finished, now.subtract(const Duration(days: 1)));
    await reminders.markDone(finished);
    scheduler.currentAccess = const ReminderAccess(
      notifications: true,
      exactAlarms: false,
    );

    await pumpApp(tester, at: '/reminders');

    expect(find.text('Reminders'), findsOneWidget);
    expect(find.text('3 NOTES'), findsOneWidget);
    final overdue = tester.getTopLeft(find.text('OVERDUE')).dy;
    final today = tester.getTopLeft(find.text('TODAY')).dy;
    final upcoming = tester.getTopLeft(find.text('UPCOMING')).dy;
    expect(overdue, lessThan(today));
    expect(today, lessThan(upcoming));
    expect(
      tester.getTopLeft(find.text('Call the bank')).dy,
      allOf(greaterThan(overdue), lessThan(today)),
    );
    expect(
      tester.getTopLeft(find.text('Renew passport')).dy,
      greaterThan(upcoming),
    );
    expect(find.text('Finished'), findsNothing);

    expect(find.text('MAY RING LATE'), findsOneWidget);
    await tester.tap(find.text('Allow exact alarms'));
    await settle(tester);
    expect(scheduler.exactAlarmRequests, 1);
  });

  testWidgets('notifications refused for good lead to the app settings', (
    tester,
  ) async {
    scheduler
      ..currentAccess = const ReminderAccess(
        notifications: false,
        exactAlarms: true,
      )
      ..grantOnRequest = false;
    await pumpApp(tester, at: '/reminders');

    expect(find.text('Nothing waiting to ring'), findsOneWidget);
    expect(find.text('NOTIFICATIONS ARE OFF'), findsOneWidget);
    await tester.tap(find.text('Allow notifications'));
    await settle(tester);

    expect(scheduler.settingsOpened, 1);
  });

  testWidgets('the drawer leads to reminders', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip('Open menu'));
    await settle(tester);
    await tester.tap(find.text('Reminders'));
    await settle(tester);

    expect(find.byType(RemindersScreen), findsOneWidget);
  });

  test('grouping leaves out finished reminders; a repeat is never overdue', () {
    // 15 September 2026 is a Tuesday.
    final now = DateTime(2026, 9, 15, 10);
    Note note(
      String title,
      DateTime at, {
      ReminderRule? rule,
      bool done = false,
    }) => Note(
      id: title,
      type: NoteType.text,
      title: title,
      body: '',
      pigment: Pigment.graphite,
      sortKey: 'm',
      createdAt: now,
      updatedAt: now,
      reminderAt: at,
      reminderRule: rule,
      reminderDone: done,
    );

    final groups = groupReminders([
      // Tuesdays at 09:00: today's has passed, so it rings next week.
      note('Weekly', DateTime(2026, 9, 1, 9), rule: ReminderRule.weekly),
      note('Finished', DateTime(2026, 9, 14, 9), done: true),
      note('Evening', DateTime(2026, 9, 15, 18)),
      note('Late', DateTime(2026, 9, 15, 9)),
    ], now: now);

    expect(
      [
        for (final (label, notes) in groups)
          '$label: ${notes.map((note) => note.title).join(', ')}',
      ],
      ['OVERDUE: Late', 'TODAY: Evening', 'UPCOMING: Weekly'],
    );
  });
}
