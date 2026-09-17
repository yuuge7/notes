import 'dart:async';
import 'dart:io';

import 'package:notes/core/util/app_version.dart';
import 'package:notes/data/backup/document_picker.dart';
import 'package:notes/data/db/database.dart';
import 'package:notes/data/db/note_dao.dart';
import 'package:notes/data/device/phone_system.dart';
import 'package:notes/data/media/compress_image_processor.dart';
import 'package:notes/data/media/image_processor.dart';
import 'package:notes/data/media/media_janitor.dart';
import 'package:notes/data/media/media_store.dart';
import 'package:notes/data/media/photo_source.dart';
import 'package:notes/data/notifications/notification_reminder_scheduler.dart';
import 'package:notes/data/reminders/reminder_sync.dart';
import 'package:notes/data/repository/attachment_repository.dart';
import 'package:notes/data/repository/backup_repository.dart';
import 'package:notes/data/repository/checklist_repository.dart';
import 'package:notes/data/repository/label_repository.dart';
import 'package:notes/data/repository/note_repository.dart';
import 'package:notes/data/repository/reminder_repository.dart';
import 'package:notes/data/repository/search_repository.dart';
import 'package:notes/data/repository/settings_repository.dart';
import 'package:notes/domain/model/settings.dart';
import 'package:notes/domain/service/reminder_scheduler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'providers.g.dart';

@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
}

@Riverpod(keepAlive: true)
NoteDao noteDao(Ref ref) => ref.watch(appDatabaseProvider).noteDao;

@Riverpod(keepAlive: true)
NoteRepository noteRepository(Ref ref) =>
    NoteRepository(ref.watch(noteDaoProvider));

@Riverpod(keepAlive: true)
ChecklistRepository checklistRepository(Ref ref) =>
    ChecklistRepository(ref.watch(noteDaoProvider));

@Riverpod(keepAlive: true)
LabelRepository labelRepository(Ref ref) =>
    LabelRepository(ref.watch(noteDaoProvider));

@Riverpod(keepAlive: true)
SearchRepository searchRepository(Ref ref) =>
    SearchRepository(ref.watch(appDatabaseProvider).searchDao);

@Riverpod(keepAlive: true)
ReminderRepository reminderRepository(Ref ref) =>
    ReminderRepository(ref.watch(noteDaoProvider));

@Riverpod(keepAlive: true)
SettingsRepository settingsRepository(Ref ref) =>
    SettingsRepository(ref.watch(appDatabaseProvider).preferenceDao);

/// The settings, now and after every change. Held for the app's life: the
/// theme, the editor, and the trash all read it.
@Riverpod(keepAlive: true)
Stream<AppSettings> appSettings(Ref ref) =>
    ref.watch(settingsRepositoryProvider).watch();

/// The app's documents directory, which images are stored under. Tests point
/// it at a temporary folder.
@Riverpod(keepAlive: true)
Future<Directory> mediaRoot(Ref ref) => getApplicationDocumentsDirectory();

@Riverpod(keepAlive: true)
MediaStore mediaStore(Ref ref) => MediaStore(ref.watch(mediaRootProvider.future));

/// The app's cache directory, where exports are written before they are
/// handed on. Tests point it at a temporary folder.
@Riverpod(keepAlive: true)
Future<Directory> cacheRoot(Ref ref) => getTemporaryDirectory();

/// The phone's own settings. Tests put a fake in its place.
@Riverpod(keepAlive: true)
PhoneSystem phoneSystem(Ref ref) => DevicePhoneSystem();

/// The system's pickers and share sheet. Tests put a fake in its place.
@Riverpod(keepAlive: true)
DocumentPicker documentPicker(Ref ref) => DeviceDocumentPicker();

@Riverpod(keepAlive: true)
BackupRepository backupRepository(Ref ref) => BackupRepository(
  ref.watch(appDatabaseProvider).backupDao,
  ref.watch(attachmentRepositoryProvider),
  ref.watch(mediaRootProvider.future),
  ref.watch(cacheRootProvider.future),
  appVersion: appVersion,
);

/// Compression of picked photos. Tests put a fake in its place.
@Riverpod(keepAlive: true)
ImageProcessor imageProcessor(Ref ref) => const CompressImageProcessor();

/// The photo picker and camera. Tests put a fake in its place.
@Riverpod(keepAlive: true)
PhotoSource photoSource(Ref ref) => DevicePhotoSource();

@Riverpod(keepAlive: true)
AttachmentRepository attachmentRepository(Ref ref) => AttachmentRepository(
  ref.watch(noteDaoProvider),
  ref.watch(mediaStoreProvider),
  ref.watch(imageProcessorProvider),
);

/// Sweeps away image files nothing refers to, from the moment it is first
/// read.
@Riverpod(keepAlive: true)
MediaJanitor mediaJanitor(Ref ref) {
  final janitor = MediaJanitor(
    ref.watch(attachmentRepositoryProvider),
    ref.watch(noteDaoProvider).watchAttachmentWrites(),
  )..start();
  ref.onDispose(() => unawaited(janitor.dispose()));
  return janitor;
}

/// Android's alarms and notifications. Tests put a fake in its place.
@Riverpod(keepAlive: true)
ReminderScheduler reminderScheduler(Ref ref) =>
    NotificationReminderScheduler();

/// Follows the stored reminders from the moment it is first read.
@Riverpod(keepAlive: true)
ReminderSync reminderSync(Ref ref) {
  final sync = ReminderSync(
    ref.watch(reminderRepositoryProvider),
    ref.watch(reminderSchedulerProvider),
  )..start();
  ref.onDispose(() => unawaited(sync.dispose()));
  return sync;
}
