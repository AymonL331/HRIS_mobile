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

/// What happens when an alarm fires — pure of platform so it can be tested.
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
  var confirmed = false;
  try {
    final page = await notifications.list(unreadOnly: true, limit: 10);
    confirmed = true;
    for (final n in page.items) {
      await notifier.showIfNew(n);
    }
    final matched = page.items.any((n) => n.type == p.alarm.type && (n.date == null || n.date == p.alarm.date));
    if (!matched && p.retry < 1) {
      await alarms.schedule(
        id: retryAlarmId(p.alarm),
        at: now().add(ReminderPlan.retryAfter),
        params: p.withRetry(1).toParams(),
      );
    }
  } catch (e) {
    debugPrint('reminders: could not confirm with the server: $e');
  }
  if (!confirmed && ReminderPlan.fallbackAllowed(p.alarm, await store.lastStatus())) {
    await notifier.showLocalFallback(p.alarm);
  }
  try {
    await scheduler.sync();
  } catch (e) {
    debugPrint('reminders: re-plan after alarm failed: $e');
  }
}

/// The alarm's entry point. Top-level and kept by `vm:entry-point` because the
/// plugin runs it by handle in a fresh engine — no UI, no providers, no session:
/// the connection comes from the store and the token from secure storage, the
/// way the tracking service does it.
@pragma('vm:entry-point')
Future<void> reminderAlarmCallback(int id, Map<String, dynamic> params) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final p = ReminderAlarmParams.fromParams(params);
  if (p == null) return;
  final store = PrefsReminderStore();
  final conn = await store.connection();
  if (conn == null) return;
  final token = (await SecureSessionStore().read(conn.envKey))?.token;
  if (token == null || token.isEmpty) return;

  final client = ApiClient(baseUrl: conn.baseUrl, appVersion: conn.appVersion, tokenProvider: () async => token);
  final notifier = LocalReminderNotifier(store: store);
  await notifier.initialize();
  const alarms = AndroidAlarmPort();
  try {
    await runReminderAlarm(
      p,
      store: store,
      notifications: ClientNotificationsApi(client),
      notifier: notifier,
      scheduler: ReminderScheduler(store: store, alarms: alarms, api: ClientReminderScheduleApi(client)),
      alarms: alarms,
      now: () => DateTime.now().toUtc(),
    );
  } finally {
    client.close();
  }
}
