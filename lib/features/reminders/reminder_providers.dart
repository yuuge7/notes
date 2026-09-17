import 'package:notes/data/device/phone_system.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/domain/model/note.dart';
import 'package:notes/domain/service/reminder_scheduler.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'reminder_providers.g.dart';

/// The maker to name in a hint that the phone may stop reminders ringing
/// while the app is closed, or null when there is nothing to say: the maker
/// is not known for it, or the hint has been seen through.
@riverpod
Future<String?> backgroundHint(Ref ref) async {
  final manufacturer = await ref.watch(phoneSystemProvider).manufacturer();
  final maker = backgroundKillers[manufacturer.toLowerCase()];
  if (maker == null) return null;
  if (await ref.watch(settingsRepositoryProvider).backgroundHintDone()) {
    return null;
  }
  return maker;
}

/// Notes outside the trash that carry a reminder, soonest first.
@riverpod
Stream<List<Note>> reminderNotes(Ref ref) => ref
    .watch(reminderRepositoryProvider)
    .watchAll()
    .map((rows) => [for (final (_, note) in rows) note]);

/// What Android lets reminders do. The app reads it again whenever it comes
/// back to the front, as after a visit to settings.
@riverpod
Future<ReminderAccess> reminderAccess(Ref ref) =>
    ref.watch(reminderSchedulerProvider).access();
