import 'package:notes/data/providers.dart';
import 'package:notes/domain/model/note.dart';
import 'package:notes/domain/service/reminder_scheduler.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'reminder_providers.g.dart';

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
