import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:notes/core/router/router.dart';
import 'package:notes/core/theme/app_theme.dart';
import 'package:notes/core/ui/undo.dart';
import 'package:notes/data/device/home_widgets.dart';
import 'package:notes/data/media/photo_source.dart';
import 'package:notes/data/notifications/notification_reminder_scheduler.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/domain/model/settings.dart';
import 'package:notes/features/editor/editor_outcome.dart';
import 'package:notes/features/notes/notes_providers.dart';
import 'package:notes/features/reminders/reminder_providers.dart';

class NotesApp extends ConsumerStatefulWidget {
  const NotesApp({super.key});

  @override
  ConsumerState<NotesApp> createState() => _NotesAppState();
}

class _NotesAppState extends ConsumerState<NotesApp> {
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<WidgetAction>? _widgetActions;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    unawaited(_holdFirstFrameForTheme());
    unawaited(_startReminders());
    unawaited(_startMedia());
    unawaited(_startWidgets());
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
    final context = await _navigator();
    if (context == null || !context.mounted) return;
    await openEditor(
      context,
      ref.read(noteRepositoryProvider),
      initialPhotos: lost,
    );
  }

  /// Keeps the home screen widgets showing the notes, and follows taps on
  /// them: the one that started the app, and any that come while it runs.
  Future<void> _startWidgets() async {
    final widgets = ref.read(homeWidgetsProvider);
    _widgetActions = widgets.actions.listen(
      (action) => unawaited(_onWidgetAction(action)),
    );
    await ref.read(appStartupProvider.future);
    ref.read(homeWidgetSyncProvider);
    final launch = await widgets.takeLaunchAction();
    if (launch != null) await _onWidgetAction(launch);
  }

  Future<void> _onWidgetAction(WidgetAction action) async {
    switch (action) {
      case OpenNote(:final noteId):
        await _open(noteId);
      case AddItem(:final noteId):
        await _open(noteId, addItem: true);
      case NewNote(:final feed):
        await _openNew(feed: feed);
      case NewList():
        await _openNew(asList: true);
      case AddPhotos():
        await _openNew(photos: (source) => source.pickPhotos());
      case TakePhoto():
        await _openNew(photos: (source) async => [?await source.takePhoto()]);
      case ShowFeed(feed: LabelFeed(:final labelId)):
        await _showLabel(labelId);
      case ShowFeed():
        // The grid, or its pinned notes: the app as it was left.
        break;
    }
  }

  /// Shows a label's page, as the drawer does, from under whatever was open
  /// over it. A note being edited was saved as the app went to the back.
  Future<void> _showLabel(String labelId) async {
    final context = await _navigator();
    if (context == null || !context.mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    appRouter.go('/label/$labelId');
  }

  /// Opens a new note over whatever is showing. A photo note opens only once
  /// there is a photo, as it does from the compose bar. A note started from a
  /// widget's [feed] belongs on it: pinned, or wearing its label.
  Future<void> _openNew({
    bool asList = false,
    Future<List<File>> Function(PhotoSource source)? photos,
    WidgetFeed feed = const AllFeed(),
  }) async {
    final taken = photos == null
        ? const <File>[]
        : await photos(ref.read(photoSourceProvider));
    if (photos != null && taken.isEmpty) return;
    final context = await _navigator();
    if (context == null || !context.mounted) return;
    await openEditor(
      context,
      ref.read(noteRepositoryProvider),
      startAsChecklist: asList,
      startPinned: feed is PinnedFeed,
      labelId: switch (feed) {
        LabelFeed(:final labelId) => labelId,
        _ => null,
      },
      initialPhotos: taken,
    );
  }

  /// The root navigator's context. Opened from a notification or a widget,
  /// the app may get here before its first frame has built the navigator.
  Future<BuildContext?> _navigator() async {
    var context = appRouter.routerDelegate.navigatorKey.currentContext;
    if (context == null) {
      await WidgetsBinding.instance.endOfFrame;
      context = appRouter.routerDelegate.navigatorKey.currentContext;
    }
    return context;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_widgetActions?.cancel());
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

  /// Opens a note from its notification or the widget, over whatever is
  /// showing. With [addItem], a list opens on a new item at its end.
  Future<void> _open(String noteId, {bool addItem = false}) async {
    final repository = ref.read(noteRepositoryProvider);
    final note = await repository.load(noteId);
    final context = await _navigator();
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
      addItem: addItem,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Android 12 and later draw the launch screen from the app's own night
    // mode, before any Dart runs. Holding the choice there makes the next
    // launch start in the chosen theme.
    ref.listen(
      appSettingsProvider.select((settings) => settings.value?.theme),
      (_, theme) {
        if (theme != null) {
          unawaited(ref.read(phoneSystemProvider).setNightMode(theme));
        }
      },
    );
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
