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
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => unawaited(onUndo()),
        ),
      ),
    );
}

/// Confirms an action that has no undo.
void showMessage(ScaffoldMessengerState messenger, String message) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
