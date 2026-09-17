import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:notes/app.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/db/note_dao.dart';
import 'package:notes/data/device/phone_system.dart';
import 'package:notes/data/notifications/notification_reminder_scheduler.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/data/repository/reminder_repository.dart';
import 'package:notes/domain/model/settings.dart';

/// Create, remind, fire: a note written in the app gets a reminder, and
/// Android posts its notification when the time comes.
///
/// `flutter test` uninstalls the app when it finishes, and the app's notes go
/// with it, so run this only on an emulator or phone whose Notes data may go.
/// It installs over the app already there, which keeps its permissions, so
/// install a debug build first and allow notifications and exact alarms:
///
/// ```sh
/// flutter build apk --debug
/// adb install -r build/app/outputs/flutter-apk/app-debug.apk
/// adb shell pm grant com.ionel.notes android.permission.POST_NOTIFICATIONS
/// adb shell appops set com.ionel.notes SCHEDULE_EXACT_ALARM allow
/// flutter test integration_test/reminder_rings_test.dart
/// ```
///
/// While it runs, the app keeps to a database and a media folder of its own,
/// and leaves the reminders already waiting and the theme as they are.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a note written and reminded rings', (tester) async {
    final media = Directory.systemTemp.createTempSync('notes_ring_media_');
    final db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(() async {
      await db.close();
      media.deleteSync(recursive: true);
    });
    // Notifications are numbered by row id. A row far along in the trash
    // makes this database's notes number from there, clear of the ids the
    // phone's own reminders use. Trashed in 2100, the start-up purge keeps it.
    await db.customStatement(
      'INSERT INTO notes (rowid, id, sort_key, created_at_ms, updated_at_ms, '
      "deleted, deleted_at_ms) VALUES ($_firstId, 'far-along', 'n', 0, 0, 1, "
      '4102444800000)',
    );
    await db.preferenceDao.write('seeded', 'true');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          mediaRootProvider.overrideWith((ref) async => media),
          cacheRootProvider.overrideWith((ref) async => media),
          reminderSchedulerProvider.overrideWithValue(_OwnRange()),
          phoneSystemProvider.overrideWithValue(_StillPhone()),
        ],
        child: const NotesApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Write a note from the compose bar, and close it.
    await tester.tap(find.text('Take a note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Post the letter');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Post the letter'), findsOneWidget);

    // Remind it half a minute from now.
    final note = (await db.noteDao.loadShelf(Shelf.active)).single;
    final rows = await db.noteDao.loadReminders();
    expect(rows, isEmpty);
    final at = DateTime.now().add(const Duration(seconds: 30));
    await ReminderRepository(db.noteDao).set(note.id, at);
    await tester.pump(const Duration(seconds: 2));
    final (notificationId, _) = (await db.noteDao.loadReminders()).single;
    expect(notificationId, greaterThan(_firstId));

    // Fire: the notification is posted when the time comes.
    final plugin = FlutterLocalNotificationsPlugin();
    ActiveNotification? rung;
    final deadline = at.add(const Duration(seconds: 60));
    while (rung == null && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(seconds: 1));
      final active = await plugin.getActiveNotifications();
      rung = active.where((n) => n.id == notificationId).firstOrNull;
    }

    expect(rung, isNotNull, reason: 'no notification by $deadline');
    expect(rung!.title, 'Post the letter');
    expect(
      DateTime.now().isAfter(at.subtract(const Duration(seconds: 1))),
      isTrue,
    );
    await plugin.cancel(id: notificationId);
  });
}

const _firstId = 900000;

/// The phone's real scheduler, shown only the notifications numbered from
/// [_firstId]. The app's first reminder pass cancels whatever is waiting that
/// its database does not know, and this database knows none of the phone's
/// own reminders.
class _OwnRange extends NotificationReminderScheduler {
  @override
  Future<Set<int>> pendingIds() async => {
    for (final id in await super.pendingIds())
      if (id >= _firstId) id,
  };
}

/// Keeps the theme chosen in the phone's own copy of the app: this database
/// holds the default, and applying it would reach the whole app.
class _StillPhone implements PhoneSystem {
  @override
  Future<void> setNightMode(ThemeChoice theme) async {}

  @override
  Future<String> manufacturer() async => 'Google';

  @override
  Future<bool> openBackgroundSettings() async => false;
}
