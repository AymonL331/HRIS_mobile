import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/widgets.dart';

import '../../core/auth/session_store.dart';
import '../../core/http/api_client.dart';
import 'reminder_models.dart';
import 'reminder_notifier.dart';
import 'reminder_scheduler.dart';
import 'reminder_store.dart';
import 'reminders_api.dart';

/// What an alarm carries: the stage it stands for, and whether this is the one
/// allowed retry.
class ReminderAlarmParams {
  final ReminderAlarm alarm;
  final int retry;

  const ReminderAlarmParams({required this.alarm, this.retry = 0});

  Map<String, dynamic> toParams() => {'alarm': alarm.toJson(), 'retry': retry};

  static ReminderAlarmParams? fromParams(Map<dynamic, dynamic> params) {
    final raw = params['alarm'];
    if (raw is! Map) return null;
    try {
      return ReminderAlarmParams(
        alarm: ReminderAlarm.fromJson(raw.cast<String, dynamic>()),
        retry: params['retry'] is int ? params['retry'] as int : 0,
      );
    } catch (_) {
      return null;
    }
  }

  ReminderAlarmParams withRetry(int n) => ReminderAlarmParams(alarm: alarm, retry: n);
}

/// The retry alarm sits in its own id space so the scheduler's re-plan (which
/// only knows the stage ids) neither replaces nor cancels it.
int retryAlarmId(ReminderAlarm a) => 0x20000000 + alarmIdOf(a);

/// Show every unread reminder not shown yet. Returns the page, or null when the
/// server could not be reached.
Future<NotificationPage?> showUnreadReminders(NotificationsApi notifications, ReminderNotifier notifier) async {
  final NotificationPage page;
  try {
    page = await notifications.list(unreadOnly: true, limit: 10);
  } catch (e) {
    debugPrint('reminders: could not confirm with the server: $e');
    return null;
  }
  for (final n in page.items) {
    await notifier.showIfNew(n);
  }
  return page;
}

/// What happens when a STAGE alarm fires — pure of platform so it can be tested.
///
/// THE SERVER DECIDES. The phone asks for the unread reminders and shows each
/// one it has not shown yet. An employee who already clocked in at the office
/// kiosk has no row, so nothing is shown — the alarm was only a wake-up call.
/// If the row for THIS stage is not there yet (the server tick ran late), one
/// more look two minutes on. Offline, the stage's own text is shown once, and
/// only if the last thing the phone knew says the punch is still pending.
///
/// Afterwards the alarms are re-planned, so a phone that is never opened still
/// carries tomorrow's reminders.
Future<void> runReminderAlarm(
  ReminderAlarmParams p, {
  required ReminderStore store,
  required NotificationsApi notifications,
  required ReminderNotifier notifier,
  required ReminderScheduler scheduler,
  required AlarmPort alarms,
  required DateTime Function() now,
}) async {
  final page = await showUnreadReminders(notifications, notifier);
  if (page != null) {
    final matched = page.items.any((n) => n.type == p.alarm.type && (n.date == null || n.date == p.alarm.date));
    if (!matched && p.retry < 1) {
      await alarms.schedule(
        id: retryAlarmId(p.alarm),
        at: now().add(ReminderPlan.retryAfter),
        params: p.withRetry(1).toParams(),
      );
    }
  } else if (ReminderPlan.fallbackAllowed(p.alarm, await store.lastStatus())) {
    await notifier.showLocalFallback(p.alarm);
  }
  try {
    await scheduler.sync();
  } catch (e) {
    debugPrint('reminders: re-plan after alarm failed: $e');
  }
}

/// What happens on the periodic REFRESH — the phone keeping itself current with
/// no help from the employee: any reminder not shown yet is shown (a missed
/// alarm, a phone that was offline), then the schedule — with today's punches —
/// is fetched and the alarms re-planned (a ladder HR changed, a day HR reset, a
/// clock-in made elsewhere).
Future<void> runReminderRefresh({
  required NotificationsApi notifications,
  required ReminderNotifier notifier,
  required ReminderScheduler scheduler,
}) async {
  await showUnreadReminders(notifications, notifier);
  try {
    await scheduler.sync();
  } catch (e) {
    debugPrint('reminders: refresh re-plan failed: $e');
  }
}

/// Everything a background callback needs, built from the store and secure
/// storage — no UI, no providers, no session — the way the tracking service
/// does it. Null when the phone is signed out.
Future<({ApiClient client, ReminderStore store, LocalReminderNotifier notifier, ReminderScheduler scheduler})?>
    _backgroundStack() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final store = PrefsReminderStore();
  final conn = await store.connection();
  if (conn == null) return null;
  final token = (await SecureSessionStore().read(conn.envKey))?.token;
  if (token == null || token.isEmpty) return null;
  final client = ApiClient(baseUrl: conn.baseUrl, appVersion: conn.appVersion, tokenProvider: () async => token);
  final notifier = LocalReminderNotifier(store: store);
  await notifier.initialize();
  return (
    client: client,
    store: store,
    notifier: notifier,
    scheduler: ReminderScheduler(store: store, alarms: const AndroidAlarmPort(), api: ClientReminderScheduleApi(client)),
  );
}

/// The stage alarm's entry point. Top-level and kept by `vm:entry-point`
/// because the plugin runs it by handle in a fresh engine.
@pragma('vm:entry-point')
Future<void> reminderAlarmCallback(int id, Map<String, dynamic> params) async {
  final p = ReminderAlarmParams.fromParams(params);
  if (p == null) return;
  final s = await _backgroundStack();
  if (s == null) return;
  try {
    await runReminderAlarm(
      p,
      store: s.store,
      notifications: ClientNotificationsApi(s.client),
      notifier: s.notifier,
      scheduler: s.scheduler,
      alarms: const AndroidAlarmPort(),
      now: () => DateTime.now().toUtc(),
    );
  } finally {
    s.client.close();
  }
}

/// The periodic refresh's entry point.
@pragma('vm:entry-point')
Future<void> reminderRefreshCallback() async {
  final s = await _backgroundStack();
  if (s == null) return;
  try {
    await runReminderRefresh(
      notifications: ClientNotificationsApi(s.client),
      notifier: s.notifier,
      scheduler: s.scheduler,
    );
  } finally {
    s.client.close();
  }
}
