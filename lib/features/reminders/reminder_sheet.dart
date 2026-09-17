import 'dart:async';

import 'package:flutter/material.dart';
import 'package:notes/core/theme/app_colors.dart';
import 'package:notes/core/theme/tokens.dart';
import 'package:notes/core/theme/typography.dart';
import 'package:notes/core/util/reminder_time.dart';
import 'package:notes/domain/model/reminder_rule.dart';
import 'package:notes/domain/service/reminder_scheduler.dart';
import 'package:notes/features/reminders/background_hint.dart';
import 'package:notes/features/reminders/reminder_format.dart';

/// Opens the reminder sheet for a note whose reminder is [at], or none.
///
/// Choices apply as they are made, like the labels page: a picked time is
/// set through [onSet] and closes the sheet; a new repeat on an existing
/// reminder goes through [onRepeat] at once and leaves it open; [onRemove]
/// clears it.
///
/// [access] is what Android allowed as the sheet opened. [readAccess] asks
/// again whenever the app returns to the front, as it does after "Allow exact
/// alarms" has sent the person to settings with the sheet still open.
Future<void> showReminderSheet(
  BuildContext context, {
  required DateTime? at,
  required ReminderRule? rule,
  required ReminderAccess access,
  required Future<ReminderAccess> Function() readAccess,
  required Future<void> Function(DateTime at, ReminderRule? rule) onSet,
  required Future<void> Function(ReminderRule? rule) onRepeat,
  required Future<void> Function() onRemove,
  required VoidCallback onAllowExact,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => ReminderSheet(
    at: at,
    rule: rule,
    access: access,
    readAccess: readAccess,
    onSet: onSet,
    onRepeat: onRepeat,
    onRemove: onRemove,
    onAllowExact: onAllowExact,
  ),
);

class ReminderSheet extends StatefulWidget {
  const ReminderSheet({
    required this.at,
    required this.rule,
    required this.access,
    required this.readAccess,
    required this.onSet,
    required this.onRepeat,
    required this.onRemove,
    required this.onAllowExact,
    super.key,
  });

  final DateTime? at;
  final ReminderRule? rule;
  final ReminderAccess access;
  final Future<ReminderAccess> Function() readAccess;
  final Future<void> Function(DateTime at, ReminderRule? rule) onSet;
  final Future<void> Function(ReminderRule? rule) onRepeat;
  final Future<void> Function() onRemove;
  final VoidCallback onAllowExact;

  @override
  State<ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<ReminderSheet> {
  late final DateTime? _at = widget.at;
  late ReminderRule? _rule = widget.rule;

  /// Set when a picked date and time had already passed.
  bool _pickedPast = false;

  late ReminderAccess _access = widget.access;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(_readAccess()),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _readAccess() async {
    final access = await widget.readAccess();
    if (mounted) setState(() => _access = access);
  }

  Future<void> _pick(DateTime at) async {
    await widget.onSet(at, _rule);
    if (mounted) Navigator.of(context).pop();
  }

  /// Picks how a reminder repeats. On an existing reminder the change saves
  /// at once; tapping the repeat already chosen saves nothing.
  Future<void> _setRule(ReminderRule? rule) async {
    if (rule == _rule) return;
    setState(() => _rule = rule);
    if (_at != null) await widget.onRepeat(rule);
  }

  Future<void> _remove() async {
    await widget.onRemove();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickDateAndTime() async {
    final now = DateTime.now();
    final current = _at;
    final start = current != null && current.isAfter(now)
        ? current
        : ReminderTime.tomorrowMorning(now);
    final day = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 10, 12, 31),
      helpText: 'Remind me on',
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(start),
      helpText: 'At',
    );
    if (time == null || !mounted) return;
    final at = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    if (!at.isAfter(DateTime.now())) {
      setState(() => _pickedPast = true);
      return;
    }
    await _pick(at);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    final now = DateTime.now();
    final later = ReminderTime.laterToday(now);
    final at = _at;
    final picks = [
      if (later != null)
        (label: 'Later today', icon: Icons.wb_twilight_outlined, at: later),
      (
        label: 'Tomorrow morning',
        icon: Icons.wb_sunny_outlined,
        at: ReminderTime.tomorrowMorning(now),
      ),
      (
        label: 'Next week',
        icon: Icons.date_range_outlined,
        at: ReminderTime.nextWeek(now),
      ),
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: Gap.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.sm, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        'REMINDER',
                        style: AppText.metaStrong.copyWith(
                          color: colors.inkMuted,
                        ),
                      ),
                    ),
                  ),
                  if (at != null)
                    TextButton(
                      onPressed: () => unawaited(_remove()),
                      style: TextButton.styleFrom(
                        foregroundColor: colors.danger,
                      ),
                      child: const Text('Remove'),
                    )
                  else
                    // Keeps the header the height of the button beside it.
                    const SizedBox(height: 48),
                ],
              ),
            ),
            if (at != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Gap.xl,
                  0,
                  Gap.xl,
                  Gap.md,
                ),
                child: Text(
                  ReminderFormat.full(
                    context,
                    ReminderTime.next(at, _rule, now),
                    _rule,
                  ),
                  style: AppText.noteTitle.copyWith(color: colors.ink),
                ),
              ),
            for (final pick in picks)
              _PickRow(
                label: pick.label,
                icon: pick.icon,
                detail: ReminderFormat.full(context, pick.at, null, now: now),
                onTap: () => unawaited(_pick(pick.at)),
              ),
            _PickRow(
              label: 'Pick a date and time',
              icon: Icons.edit_calendar_outlined,
              onTap: () => unawaited(_pickDateAndTime()),
            ),
            if (_pickedPast)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Gap.xl + 20 + Gap.lg,
                  0,
                  Gap.xl,
                  Gap.sm,
                ),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    'That time has passed. Pick a later one.',
                    style: AppText.ui.copyWith(color: colors.danger),
                  ),
                ),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: Gap.xl,
                vertical: Gap.sm,
              ),
              child: Divider(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Gap.xl,
                Gap.sm,
                Gap.xl,
                Gap.xs,
              ),
              child: Semantics(
                header: true,
                child: Text(
                  'REPEAT',
                  style: AppText.metaStrong.copyWith(color: colors.inkMuted),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
              child: Wrap(
                spacing: Gap.xs,
                children: [
                  for (final rule in <ReminderRule?>[
                    null,
                    ...ReminderRule.values,
                  ])
                    _RepeatChip(
                      label: rule?.label ?? 'Once',
                      selected: rule == _rule,
                      onTap: () => unawaited(_setRule(rule)),
                    ),
                ],
              ),
            ),
            if (!_access.exactAlarms)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Gap.xl,
                  Gap.md,
                  Gap.xl,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Android may ring reminders a few minutes late until '
                      'exact alarms are allowed.',
                      style: AppText.ui.copyWith(color: colors.inkMuted),
                    ),
                    TextButton(
                      onPressed: widget.onAllowExact,
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      child: const Text('Allow exact alarms'),
                    ),
                  ],
                ),
              )
            else
              const BackgroundHint(framed: false),
          ],
        ),
      ),
    );
  }
}

/// One way to pick a time: what it is called, and when that is.
class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.label,
    required this.icon,
    required this.onTap,
    this.detail,
  });

  final String label;
  final IconData icon;
  final String? detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    final detail = this.detail;

    return MergeSemantics(
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.xl,
                vertical: Gap.sm,
              ),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: colors.inkMuted),
                  const SizedBox(width: Gap.lg),
                  Expanded(
                    child: Text(
                      label,
                      style: AppText.uiLarge.copyWith(color: colors.ink),
                    ),
                  ),
                  if (detail != null) ...[
                    const SizedBox(width: Gap.md),
                    Flexible(
                      child: Text(
                        detail,
                        textAlign: TextAlign.end,
                        style: AppText.meta.copyWith(color: colors.inkMuted),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A repeat choice. The pill is drawn small; the target around it is the
/// full 48dp.
class _RepeatChip extends StatelessWidget {
  const _RepeatChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.chip),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.all(Gap.xs),
            child: Center(
              widthFactor: 1,
              child: AnimatedContainer(
                duration: Motion.of(context, Motion.quick),
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.md,
                  vertical: Gap.xs + 2,
                ),
                decoration: BoxDecoration(
                  color: selected ? colors.accentWash : null,
                  border: Border.all(
                    color: selected ? colors.accent : colors.hairline,
                  ),
                  borderRadius: BorderRadius.circular(Radii.chip),
                ),
                child: Text(
                  label,
                  style: (selected ? AppText.uiStrong : AppText.ui).copyWith(
                    color: selected ? colors.ink : colors.inkMuted,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
