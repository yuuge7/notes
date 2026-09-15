import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:notes/core/theme/app_colors.dart';
import 'package:notes/core/theme/tokens.dart';
import 'package:notes/core/theme/typography.dart';
import 'package:notes/core/ui/marked_text.dart';
import 'package:notes/core/util/search_text.dart';
import 'package:notes/domain/model/checklist_item.dart';
import 'package:notes/domain/model/note.dart';
import 'package:notes/features/images/image_mosaic.dart';
import 'package:notes/features/reminders/reminder_format.dart';

/// A note in the grid.
///
/// The card is paper, not paint: the pigment shows as a spine on the left edge
/// and a faint wash behind the text, so a colour-coded grid still reads as a
/// page of writing rather than a row of highlighter blocks.
class NoteCard extends StatelessWidget {
  const NoteCard({
    required this.note,
    required this.onTap,
    this.onLongPress,
    this.selected = false,
    this.dropTarget = false,
    this.semanticActions,
    this.semanticLongPress,
    this.highlight = const [],
    super.key,
  });

  final Note note;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selected;

  /// Highlights the card as the place a dragged note will land.
  final bool dropTarget;

  /// Extra actions offered to screen readers, such as moving the note.
  final Map<CustomSemanticsAction, VoidCallback>? semanticActions;

  /// Long-press for screen readers when the gesture itself belongs to a
  /// draggable, which a screen reader cannot operate.
  final VoidCallback? semanticLongPress;

  /// Search words to mark. A search result also leads with the part of the
  /// note that matched, so the reason it turned up is on the card.
  final List<String> highlight;

  /// Checklist rows shown before the card starts summarising.
  static const _previewItems = 5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colors;
    final swatch = colors.swatch(note.pigment);
    final surface = colors.surfaceFor(note.pigment);

    return Semantics(
      button: true,
      selected: selected,
      label: _semanticLabel(context),
      excludeSemantics: true,
      // The card hides its inner semantics, so it must carry the actions
      // itself or a screen reader could not open or select it.
      customSemanticsActions: semanticActions,
      onTap: onTap,
      onLongPress: onLongPress ?? semanticLongPress,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(
            color: selected || dropTarget ? colors.accent : colors.hairline,
            width: selected || dropTarget ? Stroke.selected : Stroke.hairline,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.card - Stroke.hairline),
          child: Material(
            color: dropTarget
                ? Color.alphaBlend(colors.accentWash, surface)
                : surface,
            child: InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (note.attachments.isNotEmpty)
                        ImageMosaic(images: note.attachments),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Gap.md + Stroke.spine,
                          Gap.md,
                          Gap.md,
                          Gap.sm,
                        ),
                        child: _CardBody(note: note, highlight: highlight),
                      ),
                    ],
                  ),
                  if (!note.pigment.isNone)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: Stroke.spine,
                      child: ColoredBox(color: swatch.spine),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _semanticLabel(BuildContext context) {
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
      ?_reminderLabel(context),
      if (!note.pigment.isNone) note.pigment.label,
    ];
    return parts.join('. ');
  }

  /// `Reminder, overdue: yesterday 9:00 am`, or null without a reminder.
  String? _reminderLabel(BuildContext context) {
    final next = note.nextReminderAt;
    if (next == null) return null;
    final state = note.isReminderOverdue
        ? ', overdue'
        : note.reminderDone
        ? ', done'
        : '';
    final when = ReminderFormat.full(context, next, note.reminderRule);
    return 'Reminder$state: ${when.toLowerCase()}';
  }

  /// Trims closing punctuation so joining parts with ". " never reads out a
  /// doubled stop, as in "down to the metal.. Moss".
  static String _sentence(String text) =>
      text.trim().replaceFirst(RegExp(r'[.!?…]+$'), '');
}

class _CardBody extends StatelessWidget {
  const _CardBody({required this.note, required this.highlight});

  final Note note;
  final List<String> highlight;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    final hasTitle = note.title.trim().isNotEmpty;
    final hasBody = note.body.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasTitle)
          MarkedText(
            note.title,
            terms: highlight,
            style: AppText.noteTitle.copyWith(color: colors.ink),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        if (hasTitle && (hasBody || note.isChecklist))
          const SizedBox(height: Gap.sm),
        if (note.isChecklist)
          _ChecklistPreview(note: note, highlight: highlight)
        else if (hasBody)
          _BodyPreview(body: note.body, highlight: highlight),
        if (!hasTitle &&
            !hasBody &&
            !note.isChecklist &&
            note.attachments.isEmpty)
          Text(
            'Empty note',
            style: AppText.noteBody.copyWith(color: colors.inkMuted),
          ),
        const SizedBox(height: Gap.md),
        _CardMeta(note: note, highlight: highlight),
      ],
    );
  }
}

/// The body, opened at its first match when that match would otherwise sit
/// below the lines the card shows.
class _BodyPreview extends StatelessWidget {
  const _BodyPreview({required this.body, required this.highlight});

  final String body;
  final List<String> highlight;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    final matches = SearchText.matches(body, highlight);
    final snippet = SearchText.snippet(body, matches);

    return MarkedText(
      snippet.text,
      ranges: [
        for (final (start, end) in matches)
          if (start + snippet.shift >= 0)
            (start + snippet.shift, end + snippet.shift),
      ],
      style: AppText.noteBody.copyWith(color: colors.ink),
      maxLines: 9,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _ChecklistPreview extends StatelessWidget {
  const _ChecklistPreview({required this.note, required this.highlight});

  final Note note;
  final List<String> highlight;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    // Unchecked work comes first on a card: what is left is the point. In a
    // search result the items that matched come before both.
    var ordered = [...note.uncheckedItems, ...note.checkedItems];
    if (highlight.isNotEmpty) {
      bool hit(ChecklistItem item) =>
          SearchText.matches(item.text, highlight).isNotEmpty;
      ordered = [...ordered.where(hit), ...ordered.where((i) => !hit(i))];
    }
    final shown = ordered.take(NoteCard._previewItems).toList();
    final hidden = ordered.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final item in shown)
          _ChecklistRow(item: item, highlight: highlight),
        if (hidden > 0)
          Padding(
            padding: const EdgeInsets.only(top: Gap.xs),
            child: Text(
              '+$hidden more',
              style: AppText.metaCompact.copyWith(color: colors.inkMuted),
            ),
          ),
      ],
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({required this.item, required this.highlight});

  final ChecklistItem item;
  final List<String> highlight;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    return Padding(
      padding: EdgeInsets.only(
        top: 3,
        bottom: 3,
        left: item.indent * Gap.lg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(
              item.checked
                  ? Icons.check_box_outlined
                  : Icons.check_box_outline_blank,
              size: 15,
              color: item.checked ? colors.inkMuted : colors.ink,
            ),
          ),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: MarkedText(
              item.text,
              terms: highlight,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.noteBody.copyWith(
                fontSize: 14,
                color: item.checked ? colors.inkMuted : colors.ink,
                decoration: item.checked ? TextDecoration.lineThrough : null,
                decorationColor: colors.inkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Labels, reminder, and capture time. Mono throughout: this row is record,
/// not content.
///
/// One wrap rather than a row: chips sit left and the time sits right while
/// they fit on a line, and the time drops to its own line when they do not.
/// A narrow card at large text sizes gets a taller footer instead of an
/// overflow.
class _CardMeta extends StatelessWidget {
  const _CardMeta({required this.note, required this.highlight});

  final Note note;
  final List<String> highlight;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    // Only two chips fit, so a label that matched a search takes a place
    // first.
    final matched = {
      for (final label in note.labels)
        if (SearchText.matches(label.name, highlight).isNotEmpty) label.id,
    };
    final labels = [
      ...note.labels.where((label) => matched.contains(label.id)),
      ...note.labels.where((label) => !matched.contains(label.id)),
    ].take(2).toList();
    final extraLabels = note.labels.length - labels.length;
    final hasChips = note.hasReminder || labels.isNotEmpty;

    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Gap.sm,
        runSpacing: Gap.xs,
        children: [
          if (hasChips)
            Wrap(
              spacing: Gap.xs,
              runSpacing: Gap.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (note.hasReminder) _ReminderChip(note: note),
                for (final label in labels)
                  _MetaChip(
                    text: label.name,
                    marked: matched.contains(label.id),
                  ),
                if (extraLabels > 0) _MetaChip(text: '+$extraLabels'),
              ],
            ),
          Text(
            _time(context, note.createdAt),
            style: AppText.metaCompact.copyWith(color: colors.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.text, this.marked = false});

  final String text;

  /// Set when a search matched this label.
  final bool marked;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 2),
      decoration: BoxDecoration(
        color: marked ? colors.mark : null,
        border: Border.all(color: colors.hairline),
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppText.metaCompact.copyWith(
          color: marked ? colors.ink : colors.inkMuted,
        ),
      ),
    );
  }
}

/// When the reminder rings next. Red once a one-off reminder is overdue,
/// struck through once it is done, and marked with a loop when it repeats.
class _ReminderChip extends StatelessWidget {
  const _ReminderChip({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    final overdue = note.isReminderOverdue;
    final done = note.reminderDone;
    final color = overdue ? colors.danger : colors.inkMuted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: overdue ? color : colors.hairline),
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(done ? Icons.alarm_off : Icons.alarm, size: 12, color: color),
          const SizedBox(width: Gap.xs),
          Flexible(
            child: Text(
              ReminderFormat.compact(context, note.nextReminderAt!),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.metaCompact.copyWith(
                color: color,
                decoration: done ? TextDecoration.lineThrough : null,
                decorationColor: color,
              ),
            ),
          ),
          if (note.reminderRule != null) ...[
            const SizedBox(width: 2),
            Icon(Icons.repeat, size: 12, color: color),
          ],
        ],
      ),
    );
  }
}

String _time(BuildContext context, DateTime value) {
  return MaterialLocalizations.of(context).formatTimeOfDay(
    TimeOfDay.fromDateTime(value),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
}
