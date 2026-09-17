import 'dart:async';

import 'package:flutter/material.dart';

/// Confirms an action that can be reversed, with Undo available for five
/// seconds.
///
/// The message names what the person just did — "Archive" produces "Note
/// archived" — and Undo reverses exactly that.
void showUndo(
  ScaffoldMessengerState messenger, {
  required String message,
  required Future<void> Function() onUndo,
}) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 5),
        persist: persistsWithAction(messenger),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => unawaited(onUndo()),
        ),
      ),
    );
}

/// Whether a bar with an action stays until it is used or dismissed.
///
/// A bar with an action otherwise stays by default, covering the bottom of
/// the page it is over. It stays only for someone moving through the screen
/// with TalkBack, who may take longer than its time to reach the action.
bool persistsWithAction(ScaffoldMessengerState messenger) =>
    MediaQuery.maybeAccessibleNavigationOf(messenger.context) ?? false;

/// Confirms an action that has no undo.
void showMessage(ScaffoldMessengerState messenger, String message) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
