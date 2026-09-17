import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/features/reminders/notification_bell.dart';
import 'package:hris_mobile/features/reminders/notification_display.dart';
import 'package:hris_mobile/features/reminders/reminder_models.dart';
import 'package:hris_mobile/shared/widgets/status_badge.dart';

import '../fakes/reminder_fakes.dart';

void main() {
  AppNotification n(Map<String, dynamic> j) => AppNotification.fromJson(j);

  test('tone comes from data.tone, else a _final type is urgent, else normal', () {
    expect(toneOf(n(notificationJson(tone: 'warning'))), ReminderTone.warning);
    expect(toneOf(n(notificationJson(tone: null, type: 'missing_clock_out_final'))), ReminderTone.urgent);
    expect(toneOf(n(notificationJson(tone: 'bogus', type: 'missing_clock_out_1'))), ReminderTone.normal);
    expect(toneTag(ReminderTone.warning), 'Attention');
    expect(toneTag(ReminderTone.urgent), 'Action needed');
    expect(toneTag(ReminderTone.info), isNull);
    expect(statusToneOf(ReminderTone.urgent), StatusTone.danger);
    expect(isUrgentTone(ReminderTone.info), isFalse);
  });

  test('acknowledgement state: only scored rows; overdue still open; late when after the deadline', () {
    final now = DateTime.utc(2026, 9, 11, 0, 30);
    expect(ackStateOf(n(notificationJson(ackDeadlineAt: null)), now), isNull);
    final pending = ackStateOf(n(notificationJson(ackDeadlineAt: '2026-09-11T01:00:00.000Z')), now)!;
    expect((pending.done, pending.overdue), (false, false));
    final overdue = ackStateOf(n(notificationJson(ackDeadlineAt: '2026-09-11T00:00:00.000Z')), now)!;
    expect((overdue.done, overdue.overdue), (false, true));
    final late = ackStateOf(n(notificationJson(ackDeadlineAt: '2026-09-11T00:00:00.000Z', acknowledgedAt: '2026-09-11T00:10:00.000Z')), now)!;
    expect((late.done, late.late), (true, true));
    final onTime = ackStateOf(n(notificationJson(ackDeadlineAt: '2026-09-11T01:00:00.000Z', acknowledgedAt: '2026-09-11T00:10:00.000Z')), now)!;
    expect((onTime.done, onTime.late), (true, false));
  });

  test('plain text strips the markdown markers; the badge caps at 99+', () {
    expect(plainText('Recorded as **absent** and *unpaid*'), 'Recorded as absent and unpaid');
    expect(NotificationBell.badgeText(7), '7');
    expect(NotificationBell.badgeText(120), '99+');
  });

  test('relative time', () {
    final now = DateTime.utc(2026, 9, 11, 3);
    expect(relativeTime(now.subtract(const Duration(seconds: 20)), now, (_) => 'x'), 'Just now');
    expect(relativeTime(now.subtract(const Duration(minutes: 12)), now, (_) => 'x'), '12 min ago');
    expect(relativeTime(now.subtract(const Duration(hours: 3)), now, (_) => 'x'), '3 h ago');
    expect(relativeTime(now.subtract(const Duration(days: 2)), now, (_) => 'x'), 'x');
  });

  test('the schedule and notification models parse the server shapes', () {
    final s = ReminderSchedule.fromJson(scheduleJson());
    expect(s.alarms.length, 5);
    expect(s.alarms.first.firesAt, DateTime.utc(2026, 9, 11, 0, 15));
    expect(s.alarms.first.isClockIn, isTrue);
    expect(ReminderSchedule.fromJson(s.toJson()).alarms.first.toJson(), s.alarms.first.toJson());
    expect(manilaDateOf(DateTime.utc(2026, 9, 10, 23)), '2026-09-11');
    final page = NotificationPage.fromJson({'items': [notificationJson(id: 2)], 'pagination': {'total': 7}});
    expect(page.total, 7);
    expect(page.items.single.date, '2026-09-11');
  });
}
