import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:notes/core/theme/app_colors.dart';
import 'package:notes/core/theme/tokens.dart';
import 'package:notes/core/theme/typography.dart';
import 'package:notes/core/util/checklist_rules.dart';
import 'package:notes/data/providers.dart';
import 'package:notes/data/repository/checklist_repository.dart';
import 'package:notes/domain/model/checklist_item.dart';
import 'package:notes/domain/model/note.dart';

/// The live editing state of one checklist: a text controller and focus node
/// per item, and the saves still waiting out their debounce.
///
/// The editor page owns this rather than the list widget, so the page can
/// wait for every pending save before it decides whether a note is blank.
class ChecklistEdits {
  ChecklistEdits(this._repository);

  static const _debounce = Duration(milliseconds: 400);

  final ChecklistRepository _repository;
  final _controllers = <String, TextEditingController>{};
  final _focusNodes = <String, FocusNode>{};
  final _timers = <String, Timer>{};
  final _pending = <String, String>{};

  /// The note the items belong to, once it exists.
  String? noteId;

  /// An item to focus once its row is on screen, and where the cursor goes.
  ({String itemId, int cursor})? pendingFocus;

  TextEditingController controllerFor(ChecklistItem item) => _controllers
      .putIfAbsent(item.id, () => TextEditingController(text: item.text));

  FocusNode focusFor(String itemId) =>
      _focusNodes.putIfAbsent(itemId, FocusNode.new);

  /// What the item says right now, including typing not yet saved.
  String textOf(ChecklistItem item) => _pending[item.id] ?? item.text;

  /// Brings the controllers in line with the stored items.
  ///
  /// Items that are gone lose their controller after the frame, once their
  /// row has left the tree. Text changed elsewhere, such as by a merge, is
  /// copied in unless that field is being edited.
  void sync(List<ChecklistItem> items) {
    final ids = {for (final item in items) item.id};
    final gone = [
      for (final id in _controllers.keys)
        if (!ids.contains(id)) id,
    ];
    if (gone.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final id in gone) {
          _controllers.remove(id)?.dispose();
          _focusNodes.remove(id)?.dispose();
          _timers.remove(id)?.cancel();
          _pending.remove(id);
        }
      });
    }
    for (final item in items) {
      final controller = _controllers[item.id];
      if (controller == null) continue;
      final editing =
          (_focusNodes[item.id]?.hasFocus ?? false) ||
          _pending.containsKey(item.id);
      if (!editing && controller.text != item.text) {
        controller.text = item.text;
      }
    }
  }

  /// Records typing in an item and saves it after the debounce.
  void changed(String itemId, String text) {
    final id = noteId;
    if (id == null) return;
    _pending[itemId] = text;
    _timers[itemId]?.cancel();
    _timers[itemId] = Timer(_debounce, () => unawaited(_save(id, itemId)));
  }

  Future<void> _save(String noteId, String itemId) async {
    _timers.remove(itemId);
    final text = _pending.remove(itemId);
    if (text == null) return;
    await _repository.setText(noteId, itemId, text);
  }

  /// Saves every item still waiting on its debounce.
  ///
  /// The pending text is taken synchronously, so a caller may dispose the
  /// controllers straight after calling this without losing anything.
  Future<void> flush() async {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    final pending = Map.of(_pending);
    _pending.clear();
    final id = noteId;
    if (id == null) return;
    for (final MapEntry(key: itemId, value: text) in pending.entries) {
      await _repository.setText(id, itemId, text);
    }
  }

  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final node in _focusNodes.values) {
      node.dispose();
    }
  }
}

/// A checklist on the editor page: open items that can be dragged into a new
/// order, a line to add another, and the checked items folded away below.
///
/// Built as a group of slivers so a long list is laid out lazily inside the
/// page's scroll view.
class ChecklistSection extends ConsumerStatefulWidget {
  const ChecklistSection({
    required this.note,
    required this.edits,
    required this.ensureNote,
    required this.readOnly,
    super.key,
  });

  /// Null until the note has loaded.
  final Note? note;
  final ChecklistEdits edits;

  /// Creates the note if it does not exist yet, and returns its id.
  final Future<String> Function() ensureNote;
  final bool readOnly;

  @override
  ConsumerState<ChecklistSection> createState() => _ChecklistSectionState();
}

class _ChecklistSectionState extends ConsumerState<ChecklistSection> {
  /// Checked items start folded away: what is left to do is the point.
  bool _showChecked = false;

  ChecklistRepository get _repository => ref.read(checklistRepositoryProvider);

  ChecklistEdits get _edits => widget.edits;

  void _focus(String itemId, int cursor) {
    _edits.pendingFocus = (itemId: itemId, cursor: cursor);
    if (mounted) setState(() {});
  }

  void _applyPendingFocus(List<ChecklistItem> items) {
    final pending = _edits.pendingFocus;
    if (pending == null) return;
    final item = items.where((i) => i.id == pending.itemId).firstOrNull;
    // Not stored yet: the rebuild that brings it in tries again.
    if (item == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _edits.pendingFocus != pending) return;
      _edits.pendingFocus = null;
      final controller = _edits.controllerFor(item);
      _edits.focusFor(item.id).requestFocus();
      controller.selection = TextSelection.collapsed(
        offset: pending.cursor.clamp(0, controller.text.length),
      );
    });
  }

  Future<String?> _noteId() async {
    final id = _edits.noteId ?? widget.note?.id;
    _edits.noteId = id;
    return id;
  }

  Future<void> _add() async {
    final noteId = await widget.ensureNote();
    _edits.noteId = noteId;
    await _edits.flush();
    final open = ChecklistRules.open(widget.note?.items ?? const []);
    final added = await _repository.add(
      noteId,
      afterItemId: open.isEmpty ? null : open.last.id,
      indent: 0,
    );
    _focus(added.id, 0);
  }

  void _changed(ChecklistItem item, String text) {
    if (text.contains('\n')) {
      unawaited(_splitLines(item, text));
      return;
    }
    _edits.changed(item.id, text);
  }

  /// Pasted lines become one item each, in order, below this one.
  Future<void> _splitLines(ChecklistItem item, String text) async {
    final noteId = await _noteId();
    if (noteId == null) return;
    final lines = text.split('\n');
    _edits.controllerFor(item).text = lines.first;
    await _edits.flush();
    await _repository.setText(noteId, item.id, lines.first);

    var after = item.id;
    ChecklistItem? last;
    for (final line in lines.skip(1)) {
      last = await _repository.add(noteId, afterItemId: after, text: line);
      after = last.id;
    }
    if (last != null) _focus(last.id, last.text.length);
  }

  /// Enter splits the line at the cursor: the text after it moves to a new
  /// item below, which takes the focus.
  Future<void> _split(ChecklistItem item) async {
    final noteId = await _noteId();
    if (noteId == null) return;
    final controller = _edits.controllerFor(item);
    final text = controller.text;
    final selection = controller.selection;
    final at = selection.isValid
        ? selection.start.clamp(0, text.length)
        : text.length;

    controller.text = text.substring(0, at);
    await _edits.flush();
    await _repository.setText(noteId, item.id, text.substring(0, at));
    final added = await _repository.add(
      noteId,
      afterItemId: item.id,
      text: text.substring(at),
    );
    _focus(added.id, 0);
  }

  Future<void> _mergeUp(ChecklistItem item) async {
    final noteId = await _noteId();
    if (noteId == null) return;
    await _edits.flush();
    final result = await _repository.mergeIntoPrevious(noteId, item.id);
    if (result != null) _focus(result.itemId, result.cursor);
  }

  Future<void> _setChecked(ChecklistItem item, {required bool checked}) async {
    final noteId = await _noteId();
    if (noteId == null) return;
    await _edits.flush();
    await _repository.setChecked(noteId, item.id, checked: checked);
  }

  Future<void> _setIndent(ChecklistItem item, int indent) async {
    final noteId = await _noteId();
    if (noteId == null) return;
    await _repository.setIndent(noteId, item.id, indent);
  }

  Future<void> _remove(ChecklistItem item, List<ChecklistItem> list) async {
    final noteId = await _noteId();
    if (noteId == null) return;
    final index = list.indexWhere((i) => i.id == item.id);
    final wasFocused = _edits.focusFor(item.id).hasFocus;
    await _edits.flush();
    await _repository.remove(noteId, item.id);
    if (wasFocused && index > 0) {
      final previous = list[index - 1];
      _focus(previous.id, _edits.controllerFor(previous).text.length);
    }
  }

  void _reorder(List<ChecklistItem> open, int from, int to) {
    final noteId = _edits.noteId ?? widget.note?.id;
    if (noteId == null) return;
    // The list already reports the target with the moved item taken out.
    final target = to;
    if (target == from) return;
    final rest = [...open]..removeAt(from);
    unawaited(
      _repository.move(
        noteId,
        open[from].id,
        afterItemId: target > 0 ? rest[target - 1].id : null,
        beforeItemId: target < rest.length ? rest[target].id : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    final items = note?.items ?? const <ChecklistItem>[];
    if (note != null) _edits.noteId = note.id;
    _edits.sync(items);
    _applyPendingFocus(items);

    final open = ChecklistRules.open(items);
    final done = ChecklistRules.done(items);

    return SliverMainAxisGroup(
      slivers: [
        // A new list is created with its first item as the editor opens;
        // until the note arrives there is nothing to show.
        if (note == null)
          const SliverToBoxAdapter(child: SizedBox.shrink())
        else
          SliverReorderableList(
            itemCount: open.length,
            onReorderItem: (from, to) => _reorder(open, from, to),
            proxyDecorator: (child, index, animation) =>
                Material(type: MaterialType.transparency, child: child),
            itemBuilder: (context, index) {
              final item = open[index];
              return ChecklistRow(
                key: ValueKey(item.id),
                index: index,
                item: item,
                controller: _edits.controllerFor(item),
                focusNode: _edits.focusFor(item.id),
                readOnly: widget.readOnly,
                canIndent: index > 0,
                onMoveUp: index > 0 && !widget.readOnly
                    ? () => _reorder(open, index, index - 1)
                    : null,
                onMoveDown: index < open.length - 1 && !widget.readOnly
                    ? () => _reorder(open, index, index + 1)
                    : null,
                onChanged: (text) => _changed(item, text),
                onSubmitted: () => unawaited(_split(item)),
                onBackspaceAtStart: () => unawaited(_mergeUp(item)),
                onChecked: (checked) =>
                    unawaited(_setChecked(item, checked: checked)),
                onIndent: (indent) => unawaited(_setIndent(item, indent)),
                onRemove: () => unawaited(_remove(item, open)),
              );
            },
          ),
        if (note != null && !widget.readOnly)
          SliverToBoxAdapter(child: _AddItemRow(onAdd: () => unawaited(_add()))),
        if (done.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _CheckedHeader(
              count: done.length,
              expanded: _showChecked,
              onToggle: () => setState(() => _showChecked = !_showChecked),
            ),
          ),
          if (_showChecked)
            SliverList.builder(
              itemCount: done.length,
              itemBuilder: (context, index) {
                final item = done[index];
                return ChecklistRow(
                  key: ValueKey(item.id),
                  index: index,
                  item: item,
                  controller: _edits.controllerFor(item),
                  focusNode: _edits.focusFor(item.id),
                  readOnly: widget.readOnly,
                  draggable: false,
                  canIndent: false,
                  onChanged: (text) => _changed(item, text),
                  onSubmitted: () {},
                  onBackspaceAtStart: () {},
                  onChecked: (checked) =>
                      unawaited(_setChecked(item, checked: checked)),
                  onRemove: () => unawaited(_remove(item, done)),
                );
              },
            ),
        ],
      ],
    );
  }
}

/// One item: a drag handle, a checkbox, and its text. While the text is
/// focused, the row offers indenting and removal.
class ChecklistRow extends StatefulWidget {
  const ChecklistRow({
    required this.index,
    required this.item,
    required this.controller,
    required this.focusNode,
    required this.readOnly,
    required this.onChanged,
    required this.onSubmitted,
    required this.onBackspaceAtStart,
    required this.onChecked,
    required this.onRemove,
    this.onIndent,
    this.onMoveUp,
    this.onMoveDown,
    this.draggable = true,
    this.canIndent = true,
    super.key,
  });

  final int index;
  final ChecklistItem item;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool readOnly;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;
  final VoidCallback onBackspaceAtStart;
  final ValueChanged<bool> onChecked;
  final VoidCallback onRemove;

  /// Null where indenting does not apply, such as checked items.
  final ValueChanged<int>? onIndent;

  /// Moves for people who cannot drag, offered to screen readers. Null at
  /// the ends of the list and on checked items.
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final bool draggable;

  /// False for the first open item, which has nothing to sit under.
  final bool canIndent;

  @override
  State<ChecklistRow> createState() => _ChecklistRowState();
}

class _ChecklistRowState extends State<ChecklistRow> {
  static const CustomSemanticsAction _moveUp = CustomSemanticsAction(label: 'Move up');
  static const CustomSemanticsAction _moveDown = CustomSemanticsAction(label: 'Move down');

  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _attach(widget.focusNode);
  }

  @override
  void didUpdateWidget(ChecklistRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocus);
      _attach(widget.focusNode);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  void _attach(FocusNode node) {
    node
      ..addListener(_onFocus)
      ..onKeyEvent = _onKey;
    _focused = node.hasFocus;
  }

  void _onFocus() {
    if (mounted && _focused != widget.focusNode.hasFocus) {
      setState(() => _focused = widget.focusNode.hasFocus);
    }
  }

  /// Backspace with the cursor at the very start joins this item onto the one
  /// above. The field's own node sees the key before its text editing
  /// shortcuts do, so the join happens instead of a no-op delete.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.backspace ||
        widget.readOnly) {
      return KeyEventResult.ignored;
    }
    final selection = widget.controller.selection;
    if (!selection.isCollapsed || selection.baseOffset != 0) {
      return KeyEventResult.ignored;
    }
    widget.onBackspaceAtStart();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    final item = widget.item;
    final checked = item.checked;
    final indent = checked ? 0 : item.indent;
    final textStyle = AppText.noteBodyEditor.copyWith(
      color: checked ? colors.inkMuted : colors.ink,
      decoration: checked ? TextDecoration.lineThrough : null,
      decorationColor: colors.inkMuted,
    );

    return Semantics(
      container: true,
      customSemanticsActions: {
        if (widget.onMoveUp != null) _moveUp: widget.onMoveUp!,
        if (widget.onMoveDown != null) _moveDown: widget.onMoveDown!,
      },
      child: Padding(
      padding: EdgeInsets.only(left: indent * Gap.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.draggable && !widget.readOnly)
            ReorderableDragStartListener(
              index: widget.index,
              child: Semantics(
                label: 'Drag to reorder',
                child: SizedBox(
                  width: 32,
                  height: 48,
                  child: Icon(
                    Icons.drag_indicator,
                    size: 20,
                    color: colors.inkMuted,
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: 32),
          SizedBox(
            width: 48,
            height: 48,
            child: Checkbox(
              value: checked,
              onChanged: widget.readOnly
                  ? null
                  : (value) => widget.onChecked(value ?? false),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 11, bottom: 11),
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                readOnly: widget.readOnly,
                maxLines: null,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.sentences,
                onChanged: widget.onChanged,
                onSubmitted: (_) => widget.onSubmitted(),
                // Enter is handled by onSubmitted; without this the field
                // would also hand focus to whatever comes next on the page.
                onEditingComplete: () {},
                style: textStyle,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  hintText: 'List item',
                  hintStyle: AppText.noteBodyEditor.copyWith(
                    color: colors.inkMuted,
                  ),
                ),
              ),
            ),
          ),
          if (_focused && !widget.readOnly) ...[
            if (widget.onIndent != null)
              IconButton(
                tooltip: item.indent == 0 ? 'Indent' : 'Outdent',
                onPressed: item.indent == 0 && !widget.canIndent
                    ? null
                    : () => widget.onIndent!(item.indent == 0 ? 1 : 0),
                icon: Icon(
                  item.indent == 0
                      ? Icons.format_indent_increase
                      : Icons.format_indent_decrease,
                  size: 20,
                  color: colors.inkMuted,
                ),
              ),
            IconButton(
              tooltip: 'Remove item',
              onPressed: widget.onRemove,
              icon: Icon(Icons.close, size: 20, color: colors.inkMuted),
            ),
          ],
        ],
      ),
      ),
    );
  }
}

class _AddItemRow extends StatelessWidget {
  const _AddItemRow({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    return Semantics(
      button: true,
      label: 'Add list item',
      excludeSemantics: true,
      child: InkWell(
        onTap: onAdd,
        borderRadius: BorderRadius.circular(Radii.small),
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              const SizedBox(width: 32),
              SizedBox(
                width: 48,
                child: Icon(Icons.add, size: 22, color: colors.inkMuted),
              ),
              Text(
                'List item',
                style: AppText.noteBodyEditor.copyWith(color: colors.inkMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckedHeader extends StatelessWidget {
  const _CheckedHeader({
    required this.count,
    required this.expanded,
    required this.onToggle,
  });

  final int count;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    final label = count == 1 ? '1 CHECKED ITEM' : '$count CHECKED ITEMS';

    return Padding(
      padding: const EdgeInsets.only(top: Gap.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.hairline)),
        ),
        child: Semantics(
          button: true,
          expanded: expanded,
          label: label,
          excludeSemantics: true,
          child: InkWell(
            onTap: onToggle,
            child: SizedBox(
              height: 48,
              child: Row(
                children: [
                  const SizedBox(width: 32),
                  SizedBox(
                    width: 48,
                    child: Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      color: colors.inkMuted,
                    ),
                  ),
                  Text(
                    label,
                    style: AppText.metaStrong.copyWith(color: colors.inkMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
