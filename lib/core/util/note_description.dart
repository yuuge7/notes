import 'package:notes/domain/model/note.dart';

/// A note as one sentence for a screen reader: what the card shows, in the
/// order it shows it.
///
/// Read by TalkBack on a card in the grid, and on a note in the home screen
/// widget. [reminder] is the reminder already put into words, since how a
/// time reads depends on the phone's locale and clock.
String describeNote(Note note, {String? reminder}) {
  final parts = <String>[
    if (note.pinned) 'Pinned',
    if (note.title.trim().isNotEmpty)
      _sentence(note.title)
    else
      'Untitled note',
    if (note.isChecklist)
      '${note.checkedItems.length} of ${note.items.length} done'
    else if (note.body.trim().isNotEmpty)
      _sentence(note.body),
    if (note.attachments.length == 1)
      '1 image'
    else if (note.attachments.length > 1)
      '${note.attachments.length} images',
    if (note.labels.isNotEmpty)
      'Labels: ${note.labels.map((l) => l.name).join(', ')}',
    ?reminder,
    if (!note.pigment.isNone) note.pigment.label,
  ];
  return parts.join('. ');
}

/// Trims closing punctuation so joining parts with ". " never reads out a
/// doubled stop, as in "down to the metal.. Moss".
String _sentence(String text) =>
    text.trim().replaceFirst(RegExp(r'[.!?…]+$'), '');
