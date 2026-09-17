import '../../shared/widgets/status_badge.dart';
import 'reminder_models.dart';

/// How a reminder PRESENTS itself — the website's `notificationDisplay.js`,
/// ported so the phone's bell and the browser's read the same row the same way.

enum ReminderTone { normal, info, warning, urgent }

/// The tone is carried per notification in `data.tone` (set from the firing
/// stage). Older rows that predate per-stage tones fall back to the `_final`
/// type suffix → urgent.
ReminderTone toneOf(AppNotification n) => toneFromName(n.tone) ?? (n.type.endsWith('_final') ? ReminderTone.urgent : ReminderTone.normal);

ReminderTone? toneFromName(String? name) => switch (name) {
      'normal' => ReminderTone.normal,
      'info' => ReminderTone.info,
      'warning' => ReminderTone.warning,
      'urgent' => ReminderTone.urgent,
      _ => null,
    };

/// Tones firm enough to earn a pill tag next to the title.
String? toneTag(ReminderTone tone) => switch (tone) {
      ReminderTone.warning => 'Attention',
      ReminderTone.urgent => 'Action needed',
      _ => null,
    };

StatusTone statusToneOf(ReminderTone tone) => switch (tone) {
      ReminderTone.normal => StatusTone.neutral,
      ReminderTone.info => StatusTone.info,
      ReminderTone.warning => StatusTone.warning,
      ReminderTone.urgent => StatusTone.danger,
    };

/// A firm tone gets the louder notification channel.
bool isUrgentTone(ReminderTone tone) => tone == ReminderTone.warning || tone == ReminderTone.urgent;

/// Acknowledgement state of one notification (server migration 026). Only
/// SCORED rows — those carrying an `ack_deadline_at` — can be acknowledged.
///
/// `overdue` still offers the button: the window having closed is already
/// recorded server-side and acknowledging late does not erase it, so hiding the
/// button would only deny the employee the one action left to them.
class AckState {
  final bool done;
  final bool late;
  final bool overdue;

  const AckState({required this.done, required this.late, required this.overdue});
}

AckState? ackStateOf(AppNotification n, DateTime now) {
  final deadline = n.ackDeadlineAt;
  if (deadline == null) return null;
  final ack = n.acknowledgedAt;
  if (ack != null) return AckState(done: true, late: ack.isAfter(deadline), overdue: false);
  return AckState(done: false, late: false, overdue: !deadline.isAfter(now));
}

/// Markdown markers are for a rendered body; a phone notification takes plain
/// text, so strip them rather than reading "**bold**" out to the employee.
String plainText(String? text) => (text ?? '').replaceAll(RegExp(r'\*{1,2}'), '');

/// "Just now" / "12 min ago" / "3 h ago" / a Manila date-time beyond a day.
String relativeTime(DateTime? at, DateTime now, String Function(DateTime) fallback) {
  if (at == null) return '';
  final d = now.difference(at);
  if (d.inMinutes < 1) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return fallback(at);
}
