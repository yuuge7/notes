import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:notes/core/router/router.dart';
import 'package:notes/core/theme/app_theme.dart';
import 'package:notes/core/ui/undo.dart';
import 'package:notes/data/notifications/notification_reminder_scheduler.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/domain/model/settings.dart';
import 'package:notes/features/editor/editor_outcome.dart';
import 'package:notes/features/editor/editor_screen.dart';
import 'package:notes/features/notes/notes_providers.dart';
import 'package:notes/features/reminders/reminder_providers.dart';

class NotesApp extends ConsumerStatefulWidget {
  const NotesApp({super.key});

  @override
  ConsumerState<NotesApp> createState() => _NotesAppState();
}

class _NotesAppState extends ConsumerState<NotesApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    unawaited(_holdFirstFrameForTheme());
    unawaited(_startReminders());
    unawaited(_startMedia());
  }

  /// Keeps the launch screen up until the chosen theme is known, so a person
  /// who picked dark does not see a light first frame flash by. The wait is
  /// capped: a slow or failing read shows the system theme instead.
  Future<void> _holdFirstFrameForTheme() async {
    final binding = WidgetsBinding.instance..deferFirstFrame();
    try {
      await ref
          .read(appSettingsProvider.future)
          .timeout(const Duration(seconds: 1));
    } on Object {
      // The system theme it is.
    } finally {
      binding.allowFirstFrame();
    }
  }

  /// Starts clearing away image files nothing refers to, and brings back
  /// photos picked just before Android closed the app, as a new note.
  Future<void> _startMedia() async {
    await ref.read(appStartupProvider.future);
    ref.read(mediaJanitorProvider);
    final lost = await ref.read(photoSourceProvider).recoverLost();
    if (lost.isEmpty) return;
    final context = appRouter.routerDelegate.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    final repository = ref.read(noteRepositoryProvider);
    final outcome = await Navigator.of(context).push<EditorOutcome>(
      MaterialPageRoute(builder: (_) => EditorScreen(initialPhotos: lost)),
    );
    if (context.mounted) await applyEditorOutcome(context, repository, outcome);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// Readies notifications, starts keeping them in line with the notes, and
  /// opens the note whose notification launched the app, if one did.
  Future<void> _startReminders() async {
    final scheduler = ref.read(reminderSchedulerProvider);
    if (scheduler is NotificationReminderScheduler) {
      await scheduler.initialize(onOpen: (noteId) => unawaited(_open(noteId)));
    }
    // Expired trash goes first, so nothing about to be purged is scheduled.
    await ref.read(appStartupProvider.future);
    ref.read(reminderSyncProvider);
    if (scheduler is NotificationReminderScheduler) {
      final noteId = await scheduler.launchedNoteId();
      if (noteId != null) await _open(noteId);
    }
  }

  /// Back from settings, a permission may have changed.
  void _onResume() {
    ref.invalidate(reminderAccessProvider);
    unawaited(ref.read(reminderSyncProvider).refresh());
  }

  /// Opens a note from its notification, over whatever is showing.
  Future<void> _open(String noteId) async {
    final repository = ref.read(noteRepositoryProvider);
    final note = await repository.load(noteId);
    final context = appRouter.routerDelegate.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    if (note == null) {
      showMessage(ScaffoldMessenger.of(context), 'That note has been deleted');
      return;
    }
    await openEditor(
      context,
      repository,
      noteId: noteId,
      readOnly: note.deleted,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(
      appSettingsProvider.select((settings) => settings.value?.theme),
    );
    return MaterialApp.router(
      title: 'Notes',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // The theme cross-fades when changed, unless motion is turned down.
      themeAnimationStyle: MediaQuery.maybeDisableAnimationsOf(context) ?? false
          ? AnimationStyle.noAnimation
          : null,
      themeMode: switch (theme) {
        ThemeChoice.light => ThemeMode.light,
        ThemeChoice.dark => ThemeMode.dark,
        ThemeChoice.system || null => ThemeMode.system,
      },
      routerConfig: appRouter,
      builder: (context, child) {
        // Edge-to-edge: the ground colour runs under the status and gesture
        // bars, and their icons follow the active theme.
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
              .copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarContrastEnforced: false,
              ),
          child: child!,
        );
      },
    );
  }
}
