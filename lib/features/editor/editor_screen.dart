import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:notes/core/theme/app_colors.dart';
import 'package:notes/core/theme/tokens.dart';
import 'package:notes/core/theme/typography.dart';
import 'package:notes/core/ui/undo.dart';
import 'package:notes/core/util/share_text.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/data/repository/checklist_repository.dart';
import 'package:notes/data/repository/label_repository.dart';
import 'package:notes/data/repository/note_repository.dart';
import 'package:notes/domain/model/label.dart';
import 'package:notes/domain/model/note.dart';
import 'package:notes/domain/model/note_type.dart';
import 'package:notes/domain/model/pigment.dart';
import 'package:notes/features/editor/checklist_section.dart';
import 'package:notes/features/editor/editor_outcome.dart';
import 'package:notes/features/editor/pigment_sheet.dart';
import 'package:notes/features/images/add_image_sheet.dart';
import 'package:notes/features/images/image_strip.dart';
import 'package:notes/features/images/image_viewer.dart';
import 'package:notes/features/labels/label_picker.dart';
import 'package:notes/features/labels/label_providers.dart';
import 'package:notes/features/notes/notes_providers.dart';
import 'package:notes/features/reminders/reminder_chip.dart';
import 'package:notes/features/reminders/reminder_sheet.dart';
import 'package:share_plus/share_plus.dart';

enum _More {
  share,
  copy,
  labels,
  showCheckboxes,
  hideCheckboxes,
  uncheckAll,
  deleteChecked,
  delete,
}

/// The full page for writing and reading one note or list.
///
/// Typing is the save: text is written 400ms after the last keystroke and
/// again when the page closes. A new text note is only created once it holds
/// something; a new list is created with its first line as the page opens, so
/// typing never races its creation. Either way, backing straight out leaves
/// no empty card behind.
class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({
    this.noteId,
    this.readOnly = false,
    this.startAsChecklist = false,
    this.startPinned = false,
    this.labelId,
    this.initialPhotos = const [],
    super.key,
  });

  /// The note to open, or null to start a new one.
  final String? noteId;

  /// Trashed notes open read-only: they can be restored or deleted, not
  /// edited.
  final bool readOnly;

  /// Whether a new note starts as a checklist. Ignored when [noteId] is set;
  /// an existing note keeps its own type.
  final bool startAsChecklist;

  /// Whether a new note starts pinned, as when it is begun from the pinned
  /// notes widget. Ignored when [noteId] is set.
  final bool startPinned;

  /// A label a new note wears from the start, as when it is written from that
  /// label's page. Ignored when [noteId] is set.
  final String? labelId;

  /// Photos a new note starts with, as when it is begun from the compose
  /// bar's photo or camera button.
  final List<File> initialPhotos;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  static const _debounceDelay = Duration(milliseconds: 400);

  late final NoteRepository _repository;
  late final ChecklistRepository _lists;
  late final LabelRepository _labels;
  late final ChecklistEdits _checklist;
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _bodyFocus = FocusNode();

  String? _noteId;
  Future<String>? _creating;
  bool _createdHere = false;
  bool _seeded = false;

  /// The note's type as last seen. Kept as a field, not read from the
  /// provider, because saving on close runs after the page has been disposed.
  late bool _isChecklist = widget.startAsChecklist;

  /// Set when the page closes through an action (archive, delete, copy), so
  /// the close does not also tidy or discard the note.
  bool _leaving = false;
  Timer? _debounce;
  late final AppLifecycleListener _lifecycle;

  // The text as last loaded or saved, so closing a note that was only read
  // does not stamp it as edited or mark it changed for sync.
  String _savedTitle = '';
  String _savedBody = '';

  // Choices made before the note exists, applied when it is created.
  Pigment _draftPigment = Pigment.graphite;
  late bool _draftPinned = widget.startPinned;

  /// Photos being compressed onto the note right now.
  int _adding = 0;

  @override
  void initState() {
    super.initState();
    _repository = ref.read(noteRepositoryProvider);
    _lists = ref.read(checklistRepositoryProvider);
    _labels = ref.read(labelRepositoryProvider);
    _checklist = ChecklistEdits(_lists);
    _lifecycle = AppLifecycleListener(onInactive: () => unawaited(_saveNow()));
    final id = widget.noteId;
    _noteId = id;
    if (id == null) {
      _seeded = true;
      // A list opens with one empty line ready to type into, so the first
      // keystrokes land in a real item instead of racing its creation.
      if (widget.startAsChecklist) unawaited(_startList());
    } else {
      unawaited(_seed(id));
    }
    if (widget.initialPhotos.isNotEmpty) {
      // After the first frame: adding looks up the page's messenger, which
      // initState cannot do yet.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_addPhotos(widget.initialPhotos)),
      );
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _debounce?.cancel();
    // Everything the save needs is read synchronously at the start of the
    // flush, before the controllers below are disposed.
    unawaited(_flush(_title.text, _body.text));
    _title.dispose();
    _body.dispose();
    _bodyFocus.dispose();
    _checklist.dispose();
    super.dispose();
  }

  Future<void> _seed(String id) async {
    final note = await _repository.load(id);
    if (!mounted || note == null) return;
    _title.text = note.title;
    _body.text = note.body;
    _savedTitle = note.title;
    _savedBody = note.body;
    setState(() {
      _isChecklist = note.isChecklist;
      _seeded = true;
    });
  }

  Future<void> _startList() async {
    final id = await _ensureNote();
    final first = await _lists.add(id);
    _checklist.pendingFocus = (itemId: first.id, cursor: 0);
    if (mounted) setState(() {});
  }

  bool get _isEmptyDraft =>
      _noteId == null &&
      _creating == null &&
      _title.text.trim().isEmpty &&
      _body.text.trim().isEmpty;

  /// A note this page created that still holds nothing, such as a new list
  /// whose first line was never typed into. Leaving it just closes the page,
  /// and the close discards it.
  bool get _isUntouchedNew {
    if (!_createdHere) return false;
    final note = _liveNote();
    final hasItemText =
        note?.items.any((item) => _checklist.textOf(item).trim().isNotEmpty) ??
        false;
    return _title.text.trim().isEmpty &&
        (_isChecklist ? !hasItemText : _body.text.trim().isEmpty) &&
        (note?.attachments.isEmpty ?? true) &&
        _adding == 0;
  }

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(
      _debounceDelay,
      () => unawaited(_save(_title.text, _body.text)),
    );
  }

  /// Saves what is typed as soon as the app starts to leave the screen,
  /// rather than when the debounce ends: Android may end the process in the
  /// background before then, and the page does not come back with it.
  /// Inactive is the first of the states on the way out, ahead of hidden by
  /// as long as the next app takes to appear.
  Future<void> _saveNow() async {
    if (widget.readOnly) return;
    _debounce?.cancel();
    await _checklist.flush();
    await _save(_title.text, _body.text);
  }

  /// Saves the title, and the body of a text note. A list has no body: its
  /// items save themselves, and a stale body is never written into it.
  Future<void> _save(String title, String body) async {
    final list = _isChecklist;
    final text = list ? '' : body;
    final nothingYet =
        _noteId == null && _creating == null && '$title$text'.trim().isEmpty;
    if (nothingYet) return;
    if (_noteId != null && title == _savedTitle && text == _savedBody) return;
    final id = await _ensureNote(title, text);
    await _repository.saveText(id, title: title, body: list ? null : text);
    _savedTitle = title;
    _savedBody = text;
  }

  Future<String> _ensureNote([String title = '', String body = '']) {
    final id = _noteId;
    if (id != null) return Future.value(id);
    return _creating ??= _create(title, body);
  }

  Future<String> _create(String title, String body) async {
    final list = _isChecklist;
    final note = await _repository.create(
      type: list ? NoteType.checklist : NoteType.text,
      title: title,
      body: list ? '' : body,
      pigment: _draftPigment,
    );
    if (_draftPinned) await _repository.setPinned(note.id, pinned: true);
    if (widget.labelId case final labelId?) {
      await _labels.setOnNotes([note.id], labelId, on: true);
    }
    _createdHere = true;
    _noteId = note.id;
    _checklist.noteId = note.id;
    _savedTitle = title;
    _savedBody = list ? '' : body;
    if (mounted) setState(() {});
    return note.id;
  }

  Future<void> _flush(String title, String body) async {
    if (widget.readOnly) return;
    await _checklist.flush();
    await _save(title, body);
    final id = _noteId ?? await _creating;
    if (id == null || _leaving) return;
    // The blank line left by one Enter too many does not stay in the list.
    if (_isChecklist) await _lists.removeEmpty(id);
    // Photos still on their way make the note more than blank.
    if (_createdHere && _adding == 0) await _repository.discardIfBlank(id);
  }

  Future<void> _togglePin({required bool pinned}) async {
    if (_isEmptyDraft) {
      setState(() => _draftPinned = !pinned);
      return;
    }
    final id = await _ensureNote(_title.text, _body.text);
    await _repository.setPinned(id, pinned: !pinned);
  }

  Future<void> _pickPigment(Pigment current) async {
    final picked = await showPigmentSheet(context, current: current);
    if (picked == null || picked == current) return;
    if (_isEmptyDraft) {
      setState(() => _draftPigment = picked);
      return;
    }
    final id = await _ensureNote(_title.text, _body.text);
    await _repository.setPigment(id, picked);
  }

  /// Saves, closes the page, and hands the result of [outcome] to whoever
  /// opened it.
  Future<void> _leave(EditorOutcome Function(String id) outcome) async {
    final navigator = Navigator.of(context);
    if (_isEmptyDraft || _isUntouchedNew) {
      navigator.pop();
      return;
    }
    _debounce?.cancel();
    await _checklist.flush();
    await _save(_title.text, _body.text);
    final id = await _ensureNote(_title.text, _body.text);
    _leaving = true;
    navigator.pop(outcome(id));
  }

  Future<void> _copy() async {
    if (_isEmptyDraft || _isUntouchedNew) return;
    final navigator = Navigator.of(context);
    _debounce?.cancel();
    await _checklist.flush();
    await _save(_title.text, _body.text);
    final source = await _ensureNote(_title.text, _body.text);
    final copy = await _repository.duplicate(source);
    await ref
        .read(attachmentRepositoryProvider)
        .copyAll(from: source, to: copy.id);
    _leaving = true;
    navigator.pop(Copied(copy.id));
  }

  Note? _liveNote() {
    final id = _noteId;
    return id == null ? null : ref.read(noteByIdProvider(id)).value;
  }

  /// Whether the page holds anything worth sharing or copying.
  bool _hasContent() {
    final note = _liveNote();
    return _title.text.trim().isNotEmpty ||
        (!_isChecklist && _body.text.trim().isNotEmpty) ||
        (note?.items.any((item) => _checklist.textOf(item).trim().isNotEmpty) ??
            false);
  }

  /// Sends the note as plain text through the system share sheet, using what
  /// is on the page now rather than what was last saved.
  Future<void> _share() async {
    final note = _liveNote();
    final items = _isChecklist && note != null
        ? [
            for (final item in note.items)
              item.copyWith(text: _checklist.textOf(item)),
          ]
        : null;
    final text = shareText(
      title: _title.text,
      body: _isChecklist ? '' : _body.text,
      items: items ?? const [],
    );
    if (text.isEmpty) return;
    final subject = _title.text.trim();
    await SharePlus.instance.share(
      ShareParams(text: text, subject: subject.isEmpty ? null : subject),
    );
  }

  /// Turns the text into a list, one item per line.
  Future<void> _showCheckboxes() async {
    _debounce?.cancel();
    await _save(_title.text, _body.text);
    final id = await _ensureNote(_title.text, _body.text);
    await _lists.toChecklist(id);
    _body.text = '';
    _savedBody = '';
    if (mounted) setState(() => _isChecklist = true);
  }

  /// Turns the list back into text, one line per item.
  Future<void> _hideCheckboxes() async {
    final id = _noteId;
    if (id == null) {
      setState(() => _isChecklist = false);
      return;
    }
    await _checklist.flush();
    await _save(_title.text, _body.text);
    await _lists.toText(id);
    final note = await _repository.load(id);
    _body.text = note?.body ?? '';
    _savedBody = _body.text;
    if (mounted) setState(() => _isChecklist = false);
  }

  Future<void> _uncheckAll() async {
    final id = _noteId;
    if (id == null) return;
    await _checklist.flush();
    await _lists.uncheckAll(id);
  }

  Future<void> _deleteChecked() async {
    final id = _noteId;
    if (id == null) return;
    await _checklist.flush();
    await _lists.deleteChecked(id);
  }

  /// Saves what is typed, then opens the labels page for this note. A page
  /// with nothing on it gets a note to hang the labels on; closing it still
  /// discards that note if nothing is ever written.
  Future<void> _openLabels() async {
    if (widget.readOnly) return;
    _debounce?.cancel();
    await _checklist.flush();
    await _save(_title.text, _body.text);
    final id = await _ensureNote(_title.text, _body.text);
    if (!mounted) return;
    await showLabelPicker(context, noteIds: [id]);
  }

  /// Asks where an image should come from, then adds what comes back.
  Future<void> _chooseImages() async {
    if (widget.readOnly) return;
    final choice = await showAddImageSheet(context);
    if (choice == null) return;
    final photos = ref.read(photoSourceProvider);
    final files = switch (choice) {
      PhotoChoice.pick => await photos.pickPhotos(),
      PhotoChoice.camera => [?await photos.takePhoto()],
    };
    await _addPhotos(files);
  }

  /// Compresses [files] onto the note, creating the note first when the page
  /// has none yet. Until they are in, the page counts them.
  Future<void> _addPhotos(List<File> files) async {
    if (files.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final attachments = ref.read(attachmentRepositoryProvider);
    setState(() => _adding += files.length);
    _debounce?.cancel();
    await _checklist.flush();
    await _save(_title.text, _body.text);
    final id = await _ensureNote(_title.text, _body.text);
    final result = await attachments.addImages(id, files);
    if (mounted) setState(() => _adding -= files.length);
    if (result.failed > 0) {
      showMessage(
        messenger,
        result.failed == 1
            ? 'A photo could not be added'
            : '${result.failed} photos could not be added',
      );
    }
  }

  /// Opens the reminder sheet. The first reminder set asks Android for
  /// permission to notify, and says so plainly if it is refused.
  Future<void> _openReminder() async {
    if (widget.readOnly) return;
    final scheduler = ref.read(reminderSchedulerProvider);
    final reminders = ref.read(reminderRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final note = _liveNote();
    final access = await scheduler.access();
    if (!mounted) return;

    var set = false;
    await showReminderSheet(
      context,
      at: note?.reminderAt,
      rule: note?.reminderRule,
      access: access,
      readAccess: scheduler.access,
      onSet: (at, rule) async {
        _debounce?.cancel();
        await _checklist.flush();
        await _save(_title.text, _body.text);
        final id = await _ensureNote(_title.text, _body.text);
        await reminders.set(id, at, rule: rule);
        set = true;
      },
      onRepeat: (rule) async {
        final id = _noteId;
        if (id != null) await reminders.setRule(id, rule);
      },
      onRemove: () async {
        final previous = _liveNote();
        if (previous == null) return;
        await reminders.clear(previous.id);
        showUndo(
          messenger,
          message: 'Reminder removed',
          onUndo: () => reminders.restore(previous),
        );
      },
      onAllowExact: () => unawaited(scheduler.requestExactAlarms()),
    );

    if (!set || access.notifications) return;
    if (await scheduler.requestNotifications()) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text(
            'Notifications are off for Notes, so this reminder will not ring',
          ),
          persist: persistsWithAction(messenger),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () => unawaited(scheduler.openNotificationSettings()),
          ),
        ),
      );
  }

  /// Puts the cursor at the end of the body, as a tap on the blank page below
  /// the text would on paper.
  void _focusBody() {
    if (_bodyFocus.hasFocus) {
      // Already focused, as after back has put the keyboard away: focusing
      // again would do nothing, so ask for the keyboard directly.
      unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.show'));
    } else {
      _bodyFocus.requestFocus();
    }
    _body.selection = TextSelection.collapsed(offset: _body.text.length);
  }

  void _onMore(_More action) {
    switch (action) {
      case _More.share:
        unawaited(_share());
      case _More.copy:
        unawaited(_copy());
      case _More.labels:
        unawaited(_openLabels());
      case _More.showCheckboxes:
        unawaited(_showCheckboxes());
      case _More.hideCheckboxes:
        unawaited(_hideCheckboxes());
      case _More.uncheckAll:
        unawaited(_uncheckAll());
      case _More.deleteChecked:
        unawaited(_deleteChecked());
      case _More.delete:
        unawaited(_leave(MovedToTrash.new));
    }
  }

  Future<void> _confirmDeleteForever() async {
    final colors = Theme.of(context).colors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this note forever?'),
        content: const Text(
          'It is removed from this device and cannot be restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: colors.danger),
            child: const Text('Delete forever'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.of(context).pop(DeletedForever(_noteId!));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    final id = _noteId;
    final note = id == null ? null : ref.watch(noteByIdProvider(id)).value;
    if (note != null) _isChecklist = note.isChecklist;
    final isChecklist = _isChecklist;
    final pigment = note?.pigment ?? _draftPigment;
    final pinned = note?.pinned ?? _draftPinned;
    final archived = note?.archived ?? false;
    final hasChecked = note?.items.any((item) => item.checked) ?? false;
    // A note started from a label's page shows that label before the note
    // itself exists.
    final labels =
        note?.labels ??
        [
          if (widget.labelId case final labelId?)
            for (final label
                in ref.watch(labelsProvider).value ?? const <Label>[])
              if (label.id == labelId) label,
        ];
    // A page opened for a new note or list reads as new until it holds
    // something, even though a list is saved the moment it opens.
    final isNew =
        note == null ||
        (_createdHere &&
            _title.text.trim().isEmpty &&
            (isChecklist
                ? !note.items.any((item) => item.text.trim().isNotEmpty)
                : _body.text.trim().isEmpty) &&
            note.attachments.isEmpty &&
            _adding == 0);
    final duration = Motion.of(context, Motion.standard);

    return AnimatedContainer(
      duration: duration,
      curve: Motion.enter,
      color: colors.surfaceFor(pigment),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              _TopBar(
                readOnly: widget.readOnly,
                pinned: pinned,
                archived: archived,
                hasReminder: note?.reminderAt != null,
                onReminder: () => unawaited(_openReminder()),
                onTogglePin: () => unawaited(_togglePin(pinned: pinned)),
                onToggleArchive: () => unawaited(
                  _leave((id) => ArchiveChanged(id, archived: !archived)),
                ),
              ),
              // The pigment runs along the top of the page, as it runs down
              // the edge of the card.
              AnimatedContainer(
                duration: duration,
                height: pigment.isNone ? Stroke.hairline : Stroke.spine,
                color: pigment.isNone
                    ? colors.hairline
                    : colors.swatch(pigment).spine,
              ),
              if (widget.readOnly)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Gap.xl,
                    Gap.md,
                    Gap.xl,
                    0,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'IN TRASH · RESTORE TO EDIT',
                      style: AppText.metaStrong.copyWith(
                        color: colors.inkMuted,
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: !_seeded
                    ? const SizedBox.shrink()
                    : GestureDetector(
                        onTap: widget.readOnly || isChecklist
                            ? null
                            : _focusBody,
                        // A convenience for a finger below the text. TalkBack
                        // reaches the body field itself, so the page is not
                        // offered as an unnamed button.
                        excludeFromSemantics: true,
                        child: CustomScrollView(
                          slivers: [
                            if ((note?.attachments.isNotEmpty ?? false) ||
                                _adding > 0)
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(
                                  Gap.lg,
                                  Gap.md,
                                  Gap.lg,
                                  0,
                                ),
                                sliver: SliverToBoxAdapter(
                                  child: ImageStrip(
                                    images: note?.attachments ?? const [],
                                    adding: _adding,
                                    onOpen: (index) => unawaited(
                                      openImageViewer(
                                        context,
                                        noteId: _noteId!,
                                        index: index,
                                        readOnly: widget.readOnly,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(
                                Gap.xl,
                                Gap.sm,
                                Gap.xl,
                                0,
                              ),
                              sliver: SliverToBoxAdapter(
                                child: TextField(
                                  controller: _title,
                                  readOnly: widget.readOnly,
                                  onChanged: (_) => _onChanged(),
                                  maxLines: null,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  style: AppText.noteTitleEditor.copyWith(
                                    color: colors.ink,
                                  ),
                                  // Part of the space around the title sits
                                  // inside the field, so a tap there lands
                                  // on it and it meets the 48dp target.
                                  decoration: _plainField(
                                    'Title',
                                    AppText.noteTitleEditor,
                                    colors,
                                    padding: const EdgeInsets.only(
                                      top: Gap.sm,
                                      bottom: Gap.md,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (isChecklist)
                              SliverPadding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: Gap.sm,
                                ),
                                sliver: ChecklistSection(
                                  note: note,
                                  edits: _checklist,
                                  ensureNote: () => _ensureNote(_title.text),
                                  readOnly: widget.readOnly,
                                ),
                              )
                            else
                              SliverPadding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: Gap.xl,
                                ),
                                sliver: SliverToBoxAdapter(
                                  child: TextField(
                                    controller: _body,
                                    focusNode: _bodyFocus,
                                    readOnly: widget.readOnly,
                                    onChanged: (_) => _onChanged(),
                                    // A note begun from photos opens on the
                                    // photos, not under a keyboard.
                                    autofocus:
                                        widget.noteId == null &&
                                        widget.initialPhotos.isEmpty,
                                    minLines: 6,
                                    maxLines: null,
                                    keyboardType: TextInputType.multiline,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    style: AppText.noteBodyEditor.copyWith(
                                      color: colors.ink,
                                    ),
                                    decoration: _plainField(
                                      'Write it down',
                                      AppText.noteBodyEditor,
                                      colors,
                                    ),
                                  ),
                                ),
                              ),
                            if (note != null && note.reminderAt != null)
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(
                                  Gap.xl,
                                  Gap.md,
                                  Gap.xl,
                                  0,
                                ),
                                sliver: SliverToBoxAdapter(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: ReminderChip(
                                      note: note,
                                      onTap: widget.readOnly
                                          ? null
                                          : () => unawaited(_openReminder()),
                                    ),
                                  ),
                                ),
                              ),
                            if (labels.isNotEmpty)
                              SliverPadding(
                                // The reminder chip above already stands in
                                // its own 48dp row, so the labels follow it
                                // closely rather than a full gap further on.
                                padding: EdgeInsets.fromLTRB(
                                  Gap.xl,
                                  note != null && note.reminderAt != null
                                      ? 0
                                      : Gap.md,
                                  Gap.xl,
                                  0,
                                ),
                                sliver: SliverToBoxAdapter(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    // The chips lead back to the labels page.
                                    child: Semantics(
                                      button: !widget.readOnly,
                                      label:
                                          'Labels: ${labels.map((label) => label.name).join(', ')}',
                                      excludeSemantics: true,
                                      onTap: widget.readOnly
                                          ? null
                                          : () => unawaited(_openLabels()),
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: widget.readOnly
                                            ? null
                                            : () => unawaited(_openLabels()),
                                        // A touch target tall, with the
                                        // chips centred in it.
                                        child: Container(
                                          constraints: const BoxConstraints(
                                            minHeight: Layout.minTouch,
                                          ),
                                          alignment: Alignment.centerLeft,
                                          child: Wrap(
                                            spacing: Gap.xs,
                                            runSpacing: Gap.xs,
                                            children: [
                                              for (final label in labels)
                                                _LabelChip(name: label.name),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            const SliverToBoxAdapter(
                              child: SizedBox(height: Gap.xl),
                            ),
                          ],
                        ),
                      ),
              ),
              _BottomBar(
                readOnly: widget.readOnly,
                isChecklist: isChecklist,
                hasChecked: hasChecked,
                status: _statusLabel(
                  context,
                  note,
                  readOnly: widget.readOnly,
                  isChecklist: isChecklist,
                  isNew: isNew,
                ),
                hasContent: _hasContent,
                canCopy: () =>
                    _hasContent() ||
                    (_liveNote()?.attachments.isNotEmpty ?? false),
                onColour: () => unawaited(_pickPigment(pigment)),
                onAddImage: () => unawaited(_chooseImages()),
                onMore: _onMore,
                onRestore: () => Navigator.of(context).pop(Restored(_noteId!)),
                onDeleteForever: () => unawaited(_confirmDeleteForever()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

InputDecoration _plainField(
  String hint,
  TextStyle style,
  AppColors colors, {
  EdgeInsets padding = EdgeInsets.zero,
}) {
  return InputDecoration(
    border: InputBorder.none,
    isDense: true,
    contentPadding: padding,
    hintText: hint,
    hintStyle: style.copyWith(color: colors.inkMuted),
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.readOnly,
    required this.pinned,
    required this.archived,
    required this.hasReminder,
    required this.onReminder,
    required this.onTogglePin,
    required this.onToggleArchive,
  });

  final bool readOnly;
  final bool pinned;
  final bool archived;
  final bool hasReminder;
  final VoidCallback onReminder;
  final VoidCallback onTogglePin;
  final VoidCallback onToggleArchive;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.arrow_back, color: colors.ink),
          ),
          const Spacer(),
          if (!readOnly) ...[
            IconButton(
              tooltip: pinned ? 'Unpin' : 'Pin',
              onPressed: onTogglePin,
              icon: Icon(
                pinned ? Icons.push_pin : Icons.push_pin_outlined,
                color: pinned ? colors.accent : colors.ink,
              ),
            ),
            IconButton(
              tooltip: 'Reminder',
              onPressed: onReminder,
              icon: Icon(
                hasReminder ? Icons.alarm_on : Icons.add_alarm_outlined,
                color: hasReminder ? colors.accent : colors.ink,
              ),
            ),
            IconButton(
              tooltip: archived ? 'Unarchive' : 'Archive',
              onPressed: onToggleArchive,
              icon: Icon(
                archived ? Icons.unarchive_outlined : Icons.archive_outlined,
                color: colors.ink,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.readOnly,
    required this.isChecklist,
    required this.hasChecked,
    required this.status,
    required this.hasContent,
    required this.canCopy,
    required this.onColour,
    required this.onAddImage,
    required this.onMore,
    required this.onRestore,
    required this.onDeleteForever,
  });

  final bool readOnly;
  final bool isChecklist;
  final bool hasChecked;
  final String status;

  /// Whether there is text to share. Read when the menu opens, so it
  /// reflects typing that has not caused a rebuild.
  final bool Function() hasContent;

  /// Whether Make a copy has anything to copy: text, or images alone.
  final bool Function() canCopy;
  final VoidCallback onColour;
  final VoidCallback onAddImage;
  final ValueChanged<_More> onMore;
  final VoidCallback onRestore;
  final VoidCallback onDeleteForever;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    final statusText = Text(
      status,
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppText.metaCompact.copyWith(color: colors.inkMuted),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.hairline)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.xs,
          vertical: Gap.xs,
        ),
        child: Row(
          children: readOnly
              ? [
                  Flexible(
                    child: TextButton(
                      onPressed: onRestore,
                      child: const Text(
                        'Restore',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  Expanded(child: statusText),
                  Flexible(
                    child: TextButton(
                      onPressed: onDeleteForever,
                      style: TextButton.styleFrom(
                        foregroundColor: colors.danger,
                      ),
                      child: const Text(
                        'Delete forever',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ]
              : [
                  IconButton(
                    tooltip: 'Colour',
                    onPressed: onColour,
                    icon: Icon(Icons.palette_outlined, color: colors.ink),
                  ),
                  IconButton(
                    tooltip: 'Add image',
                    onPressed: onAddImage,
                    icon: Icon(
                      Icons.add_photo_alternate_outlined,
                      color: colors.ink,
                    ),
                  ),
                  Expanded(child: statusText),
                  PopupMenuButton<_More>(
                    tooltip: 'More',
                    icon: Icon(Icons.more_vert, color: colors.ink),
                    onSelected: onMore,
                    itemBuilder: (context) {
                      // A blank page has nothing to send or copy, and a list
                      // with nothing checked has nothing to uncheck or clear,
                      // so those items are shown but not offered.
                      final hasText = hasContent();
                      return [
                        PopupMenuItem(
                          value: _More.share,
                          enabled: hasText,
                          child: const Text('Share'),
                        ),
                        PopupMenuItem(
                          value: _More.copy,
                          enabled: canCopy(),
                          child: const Text('Make a copy'),
                        ),
                        const PopupMenuItem(
                          value: _More.labels,
                          child: Text('Labels'),
                        ),
                        if (isChecklist) ...[
                          const PopupMenuItem(
                            value: _More.hideCheckboxes,
                            child: Text('Hide checkboxes'),
                          ),
                          PopupMenuItem(
                            value: _More.uncheckAll,
                            enabled: hasChecked,
                            child: const Text('Uncheck all'),
                          ),
                          PopupMenuItem(
                            value: _More.deleteChecked,
                            enabled: hasChecked,
                            child: const Text('Delete checked items'),
                          ),
                        ] else
                          const PopupMenuItem(
                            value: _More.showCheckboxes,
                            child: Text('Show checkboxes'),
                          ),
                        const PopupMenuItem(
                          value: _More.delete,
                          child: Text('Delete'),
                        ),
                      ];
                    },
                  ),
                ],
        ),
      ),
    );
  }
}

class _LabelChip extends StatelessWidget {
  const _LabelChip({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: colors.hairline),
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
      child: Text(
        name,
        style: AppText.metaCompact.copyWith(color: colors.inkMuted),
      ),
    );
  }
}

/// `EDITED 9:12 AM` for a note, `NEW NOTE` or `NEW LIST` before one exists,
/// and `DELETED 12 SEP` for a note in the trash.
String _statusLabel(
  BuildContext context,
  Note? note, {
  required bool readOnly,
  required bool isChecklist,
  required bool isNew,
}) {
  if (note == null || isNew) return isChecklist ? 'NEW LIST' : 'NEW NOTE';
  final at = readOnly ? (note.deletedAt ?? note.updatedAt) : note.updatedAt;
  final now = DateTime.now();
  final localizations = MaterialLocalizations.of(context);
  final sameDay =
      at.year == now.year && at.month == now.month && at.day == now.day;
  final when = sameDay
      ? localizations.formatTimeOfDay(
          TimeOfDay.fromDateTime(at),
          alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
        )
      : localizations.formatShortMonthDay(at);
  return '${readOnly ? 'DELETED' : 'EDITED'} ${when.toUpperCase()}';
}
