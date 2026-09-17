import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/http/api_exception.dart';
import 'package:hris_mobile/features/reminders/reminder_models.dart';
import 'package:hris_mobile/features/reminders/reminder_notifier.dart';
import 'package:hris_mobile/features/reminders/reminder_scheduler.dart';
import 'package:hris_mobile/features/reminders/reminder_store.dart';

import '../fakes/reminder_fakes.dart';

// The fixture day: 2026-09-11 (a Friday) in Manila. 07:00 Manila = 23:00Z the day before.
final DateTime sevenAm = DateTime.utc(2026, 9, 10, 23, 0);
final DateTime noon = DateTime.utc(2026, 9, 11, 4, 0);

ReminderSchedule sched([Map<String, dynamic>? j]) => ReminderSchedule.fromJson(j ?? scheduleJson());
ReminderAlarm alarm(Map<String, dynamic> j) => ReminderAlarm.fromJson(j);

void main() {
  group('ReminderPlan.plan', () {
    test('holds every future stage of both days when nothing is punched yet', () {
      final plan = ReminderPlan.plan(sched(), const LastStatus(localDate: '2026-09-11'), sevenAm);
      expect(plan.map((a) => '${a.date} ${a.kind} ${a.triggerTime}'), [
        '2026-09-11 clock_in 08:15',
        '2026-09-11 clock_out 18:00',
        '2026-09-11 clock_out 21:30',
        '2026-09-12 clock_in 08:15',
        '2026-09-12 clock_out 18:00',
      ]);
    });

    test('a stage whose wake time has passed is not armed (90 s after the trigger)', () {
      final justAfter = alarm(alarmJson()).firesAt.add(ReminderPlan.lag);
      Iterable<String> today(DateTime now) =>
          ReminderPlan.plan(sched(), null, now).where((a) => a.date == '2026-09-11').map((a) => a.triggerTime);
      expect(today(justAfter), isNot(contains('08:15')));
      expect(today(justAfter.subtract(const Duration(seconds: 1))), contains('08:15'));
    });

    test('once clocked in, TODAY\'s clock-in ladder is dropped; tomorrow\'s stays', () {
      final st = LastStatus(localDate: '2026-09-11', clockInAt: DateTime.utc(2026, 9, 11, 0, 5));
      final plan = ReminderPlan.plan(sched(), st, sevenAm);
      expect(plan.where((a) => a.isClockIn).map((a) => a.date), ['2026-09-12']);
      expect(plan.where((a) => !a.isClockIn && a.date == '2026-09-11').length, 2);
    });

    test('once clocked out, TODAY\'s clock-out ladder is dropped', () {
      final st = LastStatus(
        localDate: '2026-09-11',
        clockInAt: DateTime.utc(2026, 9, 11, 0, 5),
        clockOutAt: DateTime.utc(2026, 9, 11, 9, 0),
      );
      final plan = ReminderPlan.plan(sched(), st, noon);
      expect(plan.map((a) => '${a.date} ${a.kind}'), ['2026-09-12 clock_in', '2026-09-12 clock_out']);
    });

    test('a status from ANOTHER day never suppresses anything', () {
      final st = LastStatus(localDate: '2026-09-10', clockInAt: DateTime.utc(2026, 9, 10, 0, 5), clockOutAt: DateTime.utc(2026, 9, 10, 9, 0));
      expect(ReminderPlan.plan(sched(), st, sevenAm).length, 5);
    });

    test('a disabled ladder arms nothing', () {
      expect(ReminderPlan.plan(sched(scheduleJson(enabled: false)), null, sevenAm), isEmpty);
    });
  });

  group('alarm ids', () {
    test('are stable per stage and day, distinct across kinds, slots and days', () {
      final a = alarm(alarmJson());
      expect(alarmIdOf(a), alarmIdOf(alarm(alarmJson())));
      final ids = {
        alarmIdOf(a),
        alarmIdOf(alarm(alarmJson(kind: 'clock_out', slot: 1))),
        alarmIdOf(alarm(alarmJson(kind: 'clock_out', slot: 2))),
        alarmIdOf(alarm(alarmJson(slot: 2))),
        alarmIdOf(alarm(alarmJson(date: '2026-09-12'))),
        alarmIdOf(alarm(alarmJson(kind: 'clock_out', slot: null, type: 'missing_clock_out_soft'))),
        alarmIdOf(alarm(alarmJson(kind: 'clock_out', slot: null, type: 'missing_clock_out_final'))),
      };
      expect(ids.length, 7);
      expect(ids.every((id) => id > 0 && id.bitLength < 32), isTrue);
    });
  });

  group('ReminderPlan.fallbackAllowed', () {
    final clockIn = alarm(alarmJson());
    final clockOut = alarm(alarmJson(kind: 'clock_out'));
    final open = LastStatus(localDate: '2026-09-11', clockInAt: DateTime.utc(2026, 9, 11, 0, 5));
    final closed = LastStatus(localDate: '2026-09-11', clockInAt: DateTime.utc(2026, 9, 11, 0, 5), clockOutAt: DateTime.utc(2026, 9, 11, 9));

    test('clock-in: allowed unless today is known and already clocked in', () {
      expect(ReminderPlan.fallbackAllowed(clockIn, null), isTrue);
      expect(ReminderPlan.fallbackAllowed(clockIn, const LastStatus(localDate: '2026-09-11')), isTrue);
      expect(ReminderPlan.fallbackAllowed(clockIn, const LastStatus(localDate: '2026-09-10', )), isTrue);
      expect(ReminderPlan.fallbackAllowed(clockIn, open), isFalse);
    });

    test('clock-out: only with a KNOWN open clock-in for that day', () {
      expect(ReminderPlan.fallbackAllowed(clockOut, null), isFalse);
      expect(ReminderPlan.fallbackAllowed(clockOut, const LastStatus(localDate: '2026-09-11')), isFalse);
      expect(ReminderPlan.fallbackAllowed(clockOut, open), isTrue);
      expect(ReminderPlan.fallbackAllowed(clockOut, closed), isFalse);
    });
  });

  group('ReminderScheduler', () {
    late InMemoryReminderStore store;
    late FakeAlarmPort alarms;
    late FakeReminderScheduleApi api;
    late DateTime now;
    late ReminderScheduler s;

    setUp(() {
      store = InMemoryReminderStore();
      alarms = FakeAlarmPort();
      api = FakeReminderScheduleApi();
      now = sevenAm;
      s = ReminderScheduler(store: store, alarms: alarms, api: api, now: () => now);
    });

    test('sync fetches, arms each wanted stage 90 s after its trigger with the stage as params, and remembers it', () async {
      await s.sync(status: const LastStatus(localDate: '2026-09-11'));
      expect(api.calls, 1);
      expect(alarms.scheduled.length, 5);
      final first = alarm(alarmJson());
      final armed = alarms.scheduled[alarmIdOf(first)]!;
      expect(armed.at, first.firesAt.add(const Duration(seconds: 90)));
      expect(armed.params['retry'], 0);
      expect((armed.params['alarm'] as Map)['type'], 'missing_clock_in_1');
      expect((await store.armed()).length, 5);
      expect(store.stored, isNotNull);
      expect(store.syncedAt, now);
    });

    test('a clock-in re-plans (the schedule is fetched every time) and cancels today\'s clock-in alarm', () async {
      await s.sync(status: const LastStatus(localDate: '2026-09-11'));
      now = now.add(const Duration(minutes: 5));
      await s.sync(status: LastStatus(localDate: '2026-09-11', clockInAt: now));
      expect(api.calls, 2, reason: 'never a stale copy: every sync asks the server');
      expect(alarms.cancelled, [alarmIdOf(alarm(alarmJson()))]);
      expect((await store.armed()).length, 4);
    });

    test('the server\'s view of today wins: a reset (no punches) re-arms the clock-in ladder, a kiosk clock-out drops the clock-out one', () async {
      // The phone believes Sofia is clocked in; the server says the day was reset.
      api.json = {...scheduleJson(), 'today': null};
      await s.sync(status: LastStatus(localDate: '2026-09-11', clockInAt: now));
      expect(alarms.scheduled.containsKey(alarmIdOf(alarm(alarmJson()))), isTrue, reason: 'clock-in stage armed again');
      expect((await store.lastStatus())!.clockInAt, isNull, reason: 'the reset is now what the phone knows');

      // The server says she clocked out at the kiosk; the phone never saw it.
      api.json = {...scheduleJson(), 'today': {'attendance_log_id': 1, 'clock_in_at': '2026-09-11T00:05:00.000Z', 'clock_out_at': '2026-09-11T01:00:00.000Z'}};
      await s.sync();
      expect(alarms.scheduled.keys.where((id) => id == alarmIdOf(alarm(alarmJson(kind: 'clock_out', slot: 1, time: '18:00')))), isEmpty);
      expect((await store.armed()).where((a) => a.date == '2026-09-11'), isEmpty, reason: 'today fully punched: nothing left today');
      expect((await store.armed()).length, 2, reason: 'tomorrow stays');
    });

    test('an old server (no `today` field) leaves the phone\'s own status in force', () async {
      final j = scheduleJson()..remove('today');
      api.json = j;
      await s.sync(status: LastStatus(localDate: '2026-09-11', clockInAt: now));
      expect((await store.lastStatus())!.clockInAt, isNotNull);
      expect(alarms.scheduled.containsKey(alarmIdOf(alarm(alarmJson()))), isFalse);
    });

    test('a fetch failure falls back to the stored schedule; with none stored, nothing changes', () async {
      api.error = const ApiException.network('offline');
      await s.sync(status: const LastStatus(localDate: '2026-09-11'));
      expect(alarms.scheduled, isEmpty);
      api.error = null;
      await s.sync();
      expect(alarms.scheduled.length, 5);
      api.error = const ApiException.network('offline');
      now = now.add(const Duration(hours: 1));
      await s.sync();
      expect(alarms.scheduled.length, 5, reason: 'stored schedule re-armed');
    });

    test('ensureRefresh registers the 5-minute background refresh once; clear cancels it with everything else', () async {
      store.conn = const ReminderConnection(baseUrl: 'http://x', envKey: 'main', appVersion: '1');
      await s.ensureRefresh();
      await s.ensureRefresh();
      expect(alarms.periodics, {reminderRefreshAlarmId: const Duration(minutes: 5)});
      await s.sync(status: const LastStatus(localDate: '2026-09-11'));
      await s.clear();
      expect(alarms.cancelled.length, 6);
      expect(alarms.periodics, isEmpty);
      expect(await store.armed(), isEmpty);
      expect(await store.connection(), isNull);
      expect(await store.schedule(), isNull);
      expect(await store.refreshArmed(), isFalse);
    });

    test('next() is the earliest armed stage still ahead', () async {
      await s.sync(status: const LastStatus(localDate: '2026-09-11'));
      expect((await s.next())!.triggerTime, '08:15');
      now = noon;
      expect((await s.next())!.triggerTime, '18:00');
    });
  });

  group('shown-key pruning', () {
    test('keeps the last three days and collapses duplicates', () {
      final entries = [
        shownEntry('srv:1', '2026-09-07'),
        shownEntry('srv:2', '2026-09-08'),
        shownEntry('srv:3', '2026-09-11'),
        shownEntry('srv:3', '2026-09-11'),
      ];
      expect(pruneShownEntries(entries, '2026-09-11').map(keyOfShownEntry), ['srv:2', 'srv:3']);
    });
  });
}
