/// A note is either free text or a list of checkable items.
///
/// Conversion between the two is lossless in one direction (lines become
/// items) and lossy in the other (checked state is dropped).
enum NoteType { text, checklist }
