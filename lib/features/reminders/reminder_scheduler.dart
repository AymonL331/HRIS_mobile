import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';

import 'reminder_alarm_callback.dart';
import 'reminder_models.dart';
import 'reminder_notifier.dart';
import 'reminder_store.dart';
import 'reminders_api.dart';

/// The one thing the scheduler asks of Android. Abstract so the planning is
/// unit-tested without an alarm manager.
abstract class AlarmPort {
  Future<bool> schedule({required int id, required DateTime at, required Map<String, dynamic> params});
  Future<bool> cancel(int id);
}

/// Exact, wakes the phone, allowed in Doze, survives a reboot. Exactness is
/// the point: a reminder set for 8:15 that lands at 8:40 is a different
/// reminder. The battery exemption the setup wizard asks for is what keeps
/// deep Doze from deferring it.
class AndroidAlarmPort implements AlarmPort {
  const AndroidAlarmPort();

  @override
  Future<bool> schedule({required int id, required DateTime at, required Map<String, dynamic> params}) =>
      AndroidAlarmManager.oneShotAt(
        at,
        id,
        reminderAlarmCallback,
        exact: true,
        wakeup: true,
        allowWhileIdle: true,
        rescheduleOnReboot: true,
        params: params,
      );

  @override
  Future<bool> cancel(int id) => AndroidAlarmManager.cancel(id);
}

/// The planning rules, pure so they can be asserted.
abstract final class ReminderPlan {
  /// The detection job ticks once a minute, aligned to :00, and writes the row
  /// on the tick AFTER the stage time — so the phone asks 90 s later, not on
  /// the second, or it would ask before there is anything to find.
  static const lag = Duration(seconds: 90);

  /// When an alarm's reminder was not there yet (the server tick ran late),
  /// one more look this much later — bounded to a single retry.
  static const retryAfter = Duration(minutes: 2);

  static DateTime wakeAt(ReminderAlarm a) => a.firesAt.add(lag);

  /// Which alarms to hold: every future stage, except the ones that can no
  /// longer apply today — the clock-in ladder once clocked in, the clock-out
  /// ladder once clocked out. (The server would find nothing anyway; not
  /// arming saves the wake-up.) Tomorrow's are always held.
  static List<ReminderAlarm> plan(ReminderSchedule schedule, LastStatus? status, DateTime now) {
    if (!schedule.enabled) return const [];
    return schedule.alarms.where((a) {
      if (!wakeAt(a).isAfter(now)) return false;
      if (status != null && a.date == status.localDate) {
        if (a.isClockIn && status.clockInAt != null) return false;
        if (!a.isClockIn && status.clockOutAt != null) return false;
      }
      return true;
    }).toList(growable: false);
  }

  /// May the offline fallback speak for this alarm? Only when the last thing
  /// the phone knew says the punch is still pending. A clock-in reminder on a
  /// day the app has not been opened is allowed (nothing says they clocked in);
  /// a clock-out reminder needs a KNOWN open clock-in for that day, or it would
  /// nag someone who never came in.
  static bool fallbackAllowed(ReminderAlarm a, LastStatus? status) {
    final sameDay = status != null && status.localDate == a.date;
    if (a.isClockIn) return !sameDay || status.clockInAt == null;
    return sameDay && status.clockInAt != null && status.clockOutAt == null;
  }
}

/// Keeps Android's alarms equal to the plan: fetch the schedule (or re-use the
/// stored one), decide which stages still apply, cancel what is no longer
/// wanted, arm the rest.
class ReminderScheduler {
  final ReminderStore store;
  final AlarmPort alarms;
  final ReminderScheduleApi api;
  final DateTime Function() now;

  /// How long a fetched schedule is trusted before it is fetched again. A
  /// status change in between (a clock-in) re-plans from the stored copy.
  static const refreshEvery = Duration(minutes: 15);

  ReminderScheduler({required this.store, required this.alarms, required this.api, DateTime Function()? now})
      : now = now ?? (() => DateTime.now().toUtc());

  /// Bring the alarms up to date. [status] is the latest clock status when the
  /// caller has one (the Time Clock); the alarm callback has none and re-plans
  /// from what was last stored.
  Future<void> sync({LastStatus? status, bool force = false}) async {
    if (status != null) await store.saveLastStatus(status);
    final schedule = await _schedule(force: force);
    if (schedule == null) return;
    await arm(schedule, status ?? await store.lastStatus());
  }

  Future<ReminderSchedule?> _schedule({required bool force}) async {
    final stored = await store.schedule();
    final t = now();
    if (!force && stored != null) {
      final last = await store.lastSyncAt();
      final fresh = last != null && t.difference(last) < refreshEvery && stored.localDate == manilaDateOf(t);
      if (fresh) return stored;
    }
    try {
      final fetched = await api.schedule();
      await store.saveSchedule(fetched);
      await store.saveLastSyncAt(t);
      return fetched;
    } catch (e) {
      debugPrint('reminders: schedule fetch failed, using the stored one: $e');
      return stored;
    }
  }

  Future<void> arm(ReminderSchedule schedule, LastStatus? status) async {
    final wanted = ReminderPlan.plan(schedule, status, now());
    final wantedIds = wanted.map(alarmIdOf).toSet();
    for (final previous in await store.armed()) {
      final id = alarmIdOf(previous);
      if (!wantedIds.contains(id)) await alarms.cancel(id);
    }
    for (final a in wanted) {
      await alarms.schedule(id: alarmIdOf(a), at: ReminderPlan.wakeAt(a), params: ReminderAlarmParams(alarm: a).toParams());
    }
    await store.saveArmed(wanted);
  }

  /// Sign-out: nothing may fire for an account that is gone.
  Future<void> clear() async {
    for (final a in await store.armed()) {
      await alarms.cancel(alarmIdOf(a));
    }
    await store.clear();
  }

  /// The next armed reminder still ahead, for Settings.
  Future<ReminderAlarm?> next() async {
    final t = now();
    final ahead = (await store.armed()).where((a) => ReminderPlan.wakeAt(a).isAfter(t)).toList()
      ..sort((a, b) => a.firesAt.compareTo(b.firesAt));
    return ahead.isEmpty ? null : ahead.first;
  }
}
