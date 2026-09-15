/// How a reminder repeats after it fires.
///
/// `null` on a note means the reminder is one-shot.
enum ReminderRule {
  daily('Daily'),
  weekly('Weekly'),
  monthly('Monthly'),
  yearly('Yearly');

  ReminderRule(this.label);

  final String label;
}
