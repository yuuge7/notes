import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:notes/core/theme/tokens.dart';
import 'package:notes/data/db/note_dao.dart';
import 'package:notes/features/labels/labels_screen.dart';
import 'package:notes/features/notes/notes_screen.dart';
import 'package:notes/features/reminders/reminders_screen.dart';
import 'package:notes/features/search/search_screen.dart';
import 'package:notes/features/settings/settings_screen.dart';
import 'package:notes/features/shelf/shelf_screen.dart';

/// The app's router.
final GoRouter appRouter = buildRouter();

/// Shelves and labels are siblings reached from the drawer. Search, the
/// labels page, and settings are pushed over whatever opened them, so back
/// returns there.
///
/// Opening a note is not a route here: a card grows into its editor with a
/// container transform, which a router page cannot express. A tapped
/// reminder notification opens its note as a plain page over whatever is
/// showing; see NotesApp.
///
/// A factory rather than only a global so tests can start from any shelf with
/// a router of their own.
GoRouter buildRouter({String initialLocation = '/'}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, state) =>
            _shelfPage(state, const NotesScreen()),
      ),
      GoRoute(
        path: '/label/:id',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id']!;
          return _shelfPage(state, NotesScreen(key: ValueKey(id), labelId: id));
        },
      ),
      GoRoute(
        path: '/reminders',
        pageBuilder: (context, state) =>
            _shelfPage(state, const RemindersScreen()),
      ),
      GoRoute(
        path: '/archive',
        pageBuilder: (context, state) =>
            _shelfPage(state, const ShelfScreen(shelf: Shelf.archived)),
      ),
      GoRoute(
        path: '/trash',
        pageBuilder: (context, state) =>
            _shelfPage(state, const ShelfScreen(shelf: Shelf.trash)),
      ),
      GoRoute(
        path: '/search',
        pageBuilder: (context, state) =>
            _shelfPage(state, const SearchScreen()),
      ),
      GoRoute(
        path: '/labels',
        builder: (context, state) => const LabelsScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
}

/// Shelves swap with a short fade: they are siblings, so nothing should slide
/// in as if it were deeper. Search fades in the same way, as a lens over the
/// page rather than a place further in.
CustomTransitionPage<void> _shelfPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: Motion.standard,
    reverseTransitionDuration: Motion.standard,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.disableAnimationsOf(context)) return child;
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Motion.enter),
        child: child,
      );
    },
  );
}
