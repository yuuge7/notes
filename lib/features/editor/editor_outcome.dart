import 'dart:io';

import 'package:flutter/material.dart';
import 'package:notes/core/ui/undo.dart';
import 'package:notes/data/repository/note_repository.dart';
import 'package:notes/features/editor/editor_screen.dart';

/// What the editor asks its opener to do once the editor has closed.
///
/// Actions that take a note off the current shelf — archive, delete, restore —
/// are applied after the close transition rather than inside the editor. A
/// card that left the grid while its editor was still shrinking back would
/// leave the transition nothing to land on.
sealed class EditorOutcome {
  const EditorOutcome();
}

final class ArchiveChanged extends EditorOutcome {
  const ArchiveChanged(this.noteId, {required this.archived});

  final String noteId;

  /// The state to apply: true archives the note, false returns it to the grid.
  final bool archived;
}

final class MovedToTrash extends EditorOutcome {
  const MovedToTrash(this.noteId);

  final String noteId;
}

final class Restored extends EditorOutcome {
  const Restored(this.noteId);

  final String noteId;
}

final class DeletedForever extends EditorOutcome {
  const DeletedForever(this.noteId);

  final String noteId;
}

/// A copy was made; the opener shows it next.
final class Copied extends EditorOutcome {
  const Copied(this.copyId);

  final String copyId;
}

/// Opens the editor as a plain page and applies whatever it hands back.
///
/// Used where there is no card to grow from, such as opening a copy, or a
/// note or a new one from a notification or the home screen widget.
Future<void> openEditor(
  BuildContext context,
  NoteRepository repository, {
  String? noteId,
  bool readOnly = false,
  bool startAsChecklist = false,
  bool startPinned = false,
  String? labelId,
  List<File> initialPhotos = const [],
}) async {
  final outcome = await Navigator.of(context).push<EditorOutcome>(
    MaterialPageRoute<EditorOutcome>(
      builder: (_) => EditorScreen(
        noteId: noteId,
        readOnly: readOnly,
        startAsChecklist: startAsChecklist,
        startPinned: startPinned,
        labelId: labelId,
        initialPhotos: initialPhotos,
      ),
    ),
  );
  if (context.mounted) await applyEditorOutcome(context, repository, outcome);
}

Future<void> applyEditorOutcome(
  BuildContext context,
  NoteRepository repository,
  EditorOutcome? outcome,
) async {
  if (outcome == null) return;
  final messenger = ScaffoldMessenger.of(context);

  switch (outcome) {
    case ArchiveChanged(:final noteId, :final archived):
      await repository.setArchived(noteId, archived: archived);
      showUndo(
        messenger,
        message: archived ? 'Note archived' : 'Note unarchived',
        onUndo: () => repository.setArchived(noteId, archived: !archived),
      );
    case MovedToTrash(:final noteId):
      await repository.delete(noteId);
      showUndo(
        messenger,
        message: 'Note moved to trash',
        onUndo: () => repository.restore(noteId),
      );
    case Restored(:final noteId):
      await repository.restore(noteId);
      showMessage(messenger, 'Note restored');
    case DeletedForever(:final noteId):
      await repository.deleteForever(noteId);
      showMessage(messenger, 'Note deleted forever');
    case Copied(:final copyId):
      showMessage(messenger, 'Copy made');
      await openEditor(context, repository, noteId: copyId);
  }
}
