import 'package:flutter/material.dart';
import 'package:notes/core/theme/app_colors.dart';
import 'package:notes/core/theme/tokens.dart';
import 'package:notes/core/theme/typography.dart';
import 'package:notes/domain/model/note.dart';
import 'package:notes/features/reminders/reminder_format.dart';

/// The reminder on the editor page: when it rings next and how it repeats.
/// Red once a one-off reminder is overdue, struck through once it is done.
class ReminderChip extends StatelessWidget {
  const ReminderChip({required this.note, this.onTap, super.key});

  /// A note with a reminder.
  final Note note;

  /// Opens the reminder sheet. Null where the note cannot be edited.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    final overdue = note.isReminderOverdue;
    final done = note.reminderDone;
    final color = overdue ? colors.danger : colors.inkMuted;
    final text = ReminderFormat.full(
      context,
      note.nextReminderAt!,
      note.reminderRule,
    );
    final state = overdue
        ? ', overdue'
        : done
        ? ', done'
        : '';

    return Semantics(
      button: onTap != null,
      label: 'Reminder$state: ${text.toLowerCase()}',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.small),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.sm,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                border: Border.all(
                  color: overdue ? colors.danger : colors.hairline,
                ),
                borderRadius: BorderRadius.circular(Radii.chip),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    done ? Icons.alarm_off : Icons.alarm,
                    size: 13,
                    color: color,
                  ),
                  const SizedBox(width: Gap.xs),
                  Flexible(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.metaCompact.copyWith(
                        color: color,
                        decoration: done ? TextDecoration.lineThrough : null,
                        decorationColor: color,
                      ),
                    ),
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
