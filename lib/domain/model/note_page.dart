import 'package:notes/domain/model/note.dart';

/// The first notes of a shelf, in order, and how many the shelf holds.
///
/// A shelf of thousands loads a page at a time: the grid reads the next page
/// as its end comes near, so a write to one note does not reload them all.
class NotePage {
  const NotePage({required this.notes, required this.total, this.after});

  final List<Note> notes;

  /// Every note on the shelf, loaded or not.
  final int total;

  /// Where the first note past the page sits, when there is one. A note moved
  /// to the end of what is loaded must still sort before it.
  final ({String sortKey, bool pinned})? after;

  bool get hasMore => notes.length < total;
}
