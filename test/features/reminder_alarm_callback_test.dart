import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/http/api_exception.dart';
import 'package:hris_mobile/features/reminders/reminder_alarm_callback.dart';
import 'package:hris_mobile/features/reminders/reminder_models.dart';
import 'package:hris_mobile/features/reminders/reminder_notifier.dart';
import 'package:hris_mobile/features/reminders/reminder_scheduler.dart';
import 'package:hris_mobile/features/reminders/reminder_store.dart';

import '../fakes/reminder_fakes.dart';

void main() {
  late InMemoryReminderStore store;
  late FakeNotificationsApi notifications;
  late FakeReminderNotifier notifier;
  late FakeAlarmPort alarms;
  late FakeReminderScheduleApi scheduleApi;
  late DateTime now;
  late ReminderScheduler scheduler;

  final clockIn = ReminderAlarm.fromJson(alarmJson());
  final clockOut = ReminderAlarm.fromJson(alarmJson(kind: 'clock_out', slot: 1, time: '18:00'));

  setUp(() {
    store = InMemoryReminderStore();
    notifications = FakeNotificationsApi();
    notifier = FakeReminderNotifier();
    alarms = FakeAlarmPort();
    scheduleApi = FakeReminderScheduleApi();
    // 08:16:30 Manila on the fixture day — the clock-in alarm's wake time.
    now = clockIn.firesAt.add(ReminderPlan.lag);
    scheduler = ReminderScheduler(store: store, alarms: alarms, api: scheduleApi, now: () => now);
  });

  Future<void> run(ReminderAlarm a, {int retry = 0}) => runReminderAlarm(
        ReminderAlarmParams(alarm: a, retry: retry),
        store: store,
        notifications: notifications,
        notifier: notifier,
        scheduler: scheduler,
        alarms: alarms,
        now: () => now,
      );

  test('the server\'s reminder rows are shown, and the alarms re-planned for what is still ahead', () async {
    notifications.rows = [notificationJson(id: 41)];
    await run(clockIn);
    expect(notifications.calls.first, 'list:unread');
    expect(notifier.shown, ['srv:41']);
    expect(alarms.scheduled.containsKey(retryAlarmId(clockIn)), isFalse, reason: 'the row was there — no retry');
    // Re-planned: the fired stage is behind us, the rest of the ladder is armed.
    expect(alarms.scheduled.containsKey(alarmIdOf(clockIn)), isFalse);
    expect(alarms.scheduled.containsKey(alarmIdOf(clockOut)), isTrue);
    expect(scheduleApi.calls, 1);
  });

  test('NO row for this stage yet (the server tick ran late) → one retry two minutes on, never a second', () async {
    await run(clockIn);
    final retry = alarms.scheduled[retryAlarmId(clockIn)];
    expect(retry, isNotNull);
    expect(retry!.at, now.add(const Duration(minutes: 2)));
    expect(retry.params['retry'], 1);
    expect(notifier.shown, isEmpty, reason: 'online and nothing sent: the kiosk case — silence');

    alarms.scheduled.clear();
    await run(clockIn, retry: 1);
    expect(alarms.scheduled.containsKey(retryAlarmId(clockIn)), isFalse);
  });

  test('a row for a DIFFERENT stage still counts as shown, but this stage still retries', () async {
    notifications.rows = [notificationJson(id: 7, type: 'missing_clock_out_1')];
    await run(clockIn);
    expect(notifier.shown, ['srv:7']);
    expect(alarms.scheduled.containsKey(retryAlarmId(clockIn)), isTrue);
  });

  test('offline: the clock-in stage speaks for itself when nothing says they clocked in', () async {
    notifications.failNext = const ApiException.network('offline');
    scheduleApi.error = const ApiException.network('offline');
    await run(clockIn);
    expect(notifier.shown, ['local:missing_clock_in_1:2026-09-11']);
    expect(alarms.scheduled.containsKey(retryAlarmId(clockIn)), isFalse, reason: 'offline is not "not yet"');
  });

  test('offline: stays silent when the last known status says the punch is already done', () async {
    store.status = LastStatus(localDate: '2026-09-11', clockInAt: DateTime.utc(2026, 9, 11, 0, 5));
    notifications.failNext = const ApiException.network('offline');
    await run(clockIn);
    expect(notifier.shown, isEmpty);
  });

  test('offline: a clock-out fallback needs a known open clock-in for that day', () async {
    notifications.failNext = const ApiException.network('offline');
    await run(clockOut);
    expect(notifier.shown, isEmpty);

    store.status = LastStatus(localDate: '2026-09-11', clockInAt: DateTime.utc(2026, 9, 11, 0, 5));
    notifications.failNext = const ApiException.network('offline');
    await run(clockOut);
    expect(notifier.shown, ['local:missing_clock_out_1:2026-09-11']);
  });

  test('params round-trip through the alarm manager\'s JSON map', () {
    final p = ReminderAlarmParams(alarm: clockIn, retry: 1);
    final back = ReminderAlarmParams.fromParams(p.toParams())!;
    expect(back.retry, 1);
    expect(back.alarm.type, clockIn.type);
    expect(back.alarm.firesAt, clockIn.firesAt);
    expect(ReminderAlarmParams.fromParams(const {'nope': 1}), isNull);
  });
}
