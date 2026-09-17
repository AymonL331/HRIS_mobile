import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_display.dart';
import 'reminder_models.dart';
import 'reminder_store.dart';

/// Where a reminder is SHOWN on the phone — the Android notification. Both the
/// signed-in app (a poll turned up a new row) and the alarm callback (no UI)
/// go through the same door, and the same shown-keys, so a reminder is never
/// announced twice however it arrived.
abstract class ReminderNotifier {
  /// Show a server reminder unless it was shown before. Returns true if shown.
  Future<bool> showIfNew(AppNotification n);

  /// Count a reminder as shown WITHOUT showing it — the bell already has it in
  /// front of the employee (a cold start's first load), so the background
  /// refresh must not announce it minutes later as if it were news.
  Future<void> markShown(AppNotification n);

  /// The phone is offline at reminder time: show the stage's own text, once,
  /// saying it could not be confirmed. Returns true if shown.
  Future<bool> showLocalFallback(ReminderAlarm a);
}

/// The tap payload that opens the Time Clock (user decision 2026-09-17).
const reminderTapTimeClock = 'time_clock';

/// Shown-key for a server row / an offline fallback.
String serverShownKey(int id) => 'srv:$id';
String localShownKey(String type, String date) => 'local:$type:$date';

/// Notification ids for the fallback live above the alarm ids so the two can
/// never collide with a server row's id (a small auto-increment).
const _fallbackIdBase = 0x40000000;

/// Body suffix for an unconfirmed reminder (user decision 2026-09-17: show it
/// anyway, but say so).
const unconfirmedSuffix = 'Could not confirm with the server.';

class LocalReminderNotifier implements ReminderNotifier {
  final ReminderStore store;
  final FlutterLocalNotificationsPlugin plugin;

  /// The Manila date of "now", for pruning the shown-keys. Injectable for tests.
  final DateTime Function() now;

  LocalReminderNotifier({required this.store, FlutterLocalNotificationsPlugin? plugin, DateTime Function()? now})
      : plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        now = now ?? (() => DateTime.now().toUtc());

  /// Two channels because Android fixes sound and importance PER CHANNEL: the
  /// ordinary nudge, and the firm one (warning / urgent stages) that also
  /// vibrates and shows as a heads-up.
  static const channelNormal = AndroidNotificationChannel(
    'clock_reminders',
    'Clock-in / clock-out reminders',
    description: 'Reminders to clock in or clock out, as set by HR.',
    importance: Importance.high,
  );
  static const channelUrgent = AndroidNotificationChannel(
    'clock_reminders_urgent',
    'Urgent clock reminders',
    description: 'Final reminders that need your action.',
    importance: Importance.max,
  );

  /// Must run once per isolate before anything is shown. [onTap] receives the
  /// payload of a tapped notification while the app is alive, and the one that
  /// launched the app if it was closed (only when [onTap] is given — the alarm
  /// callback has nowhere to route a tap).
  Future<void> initialize({void Function(String? payload)? onTap}) async {
    try {
      await plugin.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('ic_launcher_monochrome')),
        onDidReceiveNotificationResponse: onTap == null ? null : (r) => onTap(r.payload),
      );
      final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(channelNormal);
      await android?.createNotificationChannel(channelUrgent);
      if (onTap != null) {
        final launch = await plugin.getNotificationAppLaunchDetails();
        if (launch?.didNotificationLaunchApp == true) onTap(launch!.notificationResponse?.payload);
      }
    } catch (e) {
      // A host with no plugin (tests, odd devices): the bell still works, only
      // the phone notification is lost.
      debugPrint('reminders: notifier init failed: $e');
    }
  }

  @override
  Future<bool> showIfNew(AppNotification n) async {
    final shown = await store.shownKeys();
    final key = serverShownKey(n.id);
    if (shown.contains(key)) return false;
    final date = n.date ?? manilaDateOf(now());
    // The offline fallback for this very stage already told them; the server
    // row is the same reminder, not a second one.
    if (n.date != null && shown.contains(localShownKey(n.type, n.date!))) {
      await store.markShown(key, date);
      return false;
    }
    final tone = toneOf(n);
    await _show(id: n.id, title: plainText(n.title), body: plainText(n.message), urgent: isUrgentTone(tone));
    await store.markShown(key, date);
    return true;
  }

  @override
  Future<void> markShown(AppNotification n) => store.markShown(serverShownKey(n.id), n.date ?? manilaDateOf(now()));

  @override
  Future<bool> showLocalFallback(ReminderAlarm a) async {
    final shown = await store.shownKeys();
    final key = localShownKey(a.type, a.date);
    if (shown.contains(key)) return false;
    final urgent = isUrgentTone(toneFromName(a.tone) ?? ReminderTone.normal);
    await _show(
      id: _fallbackIdBase + alarmIdOf(a),
      title: plainText(a.title),
      body: '${plainText(a.message)}\n\n$unconfirmedSuffix',
      urgent: urgent,
    );
    await store.markShown(key, a.date);
    return true;
  }

  Future<void> _show({required int id, required String title, required String body, required bool urgent}) async {
    final channel = urgent ? channelUrgent : channelNormal;
    try {
      await plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            importance: channel.importance,
            priority: urgent ? Priority.max : Priority.high,
            category: AndroidNotificationCategory.reminder,
            styleInformation: BigTextStyleInformation(body),
            color: const Color(0xFF2563EB),
            ticker: title,
          ),
        ),
        payload: reminderTapTimeClock,
      );
    } catch (e) {
      debugPrint('reminders: show failed: $e');
    }
  }
}

/// A stable Android alarm id for a stage on a day: the day number × 20, plus
/// 0–9 for the clock-in ladder and 10–19 for the clock-out one (slot 1–6; the
/// built-in `_soft` takes 0 and `_final` 7). Re-arming the same stage replaces
/// the previous alarm instead of stacking a second one. Fits in 31 bits for
/// centuries.
int alarmIdOf(ReminderAlarm a) {
  final parts = a.date.split('-').map(int.tryParse).toList();
  final day = parts.length == 3 && !parts.any((p) => p == null)
      ? DateTime.utc(parts[0]!, parts[1]!, parts[2]!).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay
      : 0;
  final slot = a.slot ?? (a.type.endsWith('_final') ? 7 : 0);
  return day * 20 + (a.isClockIn ? 0 : 10) + slot.clamp(0, 9);
}
