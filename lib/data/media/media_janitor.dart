import 'dart:async';

import 'package:notes/data/repository/attachment_repository.dart';

/// Frees the files of images nothing refers to any more.
///
/// Deleting a note forever, emptying the trash, and purging expired trash take
/// the note's attachment rows with it through the database's cascade, which
/// leaves their files behind. This sweeps once at start-up, then again
/// shortly after every write to the attachments table.
class MediaJanitor {
  MediaJanitor(
    this._attachments,
    this._writes, {
    this.delay = const Duration(seconds: 1),
  });

  final AttachmentRepository _attachments;
  final Stream<void> _writes;

  /// How long writes must pause before a sweep, so a batch of deletions is
  /// swept once.
  final Duration delay;

  StreamSubscription<void>? _subscription;
  Timer? _timer;
  Future<void> _queue = Future.value();

  /// Clears what earlier runs left behind, then follows the attachments.
  void start() {
    if (_subscription != null) return;
    _subscription = _writes.listen((_) {
      _timer?.cancel();
      _timer = Timer(delay, () => _sweep(dropRemoved: false));
    });
    _sweep(dropRemoved: true);
  }

  /// Resolves once every sweep started so far has finished.
  Future<void> get idle => _queue;

  Future<void> dispose() async {
    _timer?.cancel();
    await _subscription?.cancel();
    _subscription = null;
  }

  void _sweep({required bool dropRemoved}) {
    _queue = _queue
        .then((_) => _attachments.sweep(dropRemoved: dropRemoved))
        .then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) =>
              Zone.current.handleUncaughtError(error, stack),
        );
  }
}
