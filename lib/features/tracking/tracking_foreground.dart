import 'dart:async';
import 'dart:ui';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' hide NotificationVisibility;

import '../../core/time/manila_time.dart';
import '../reminders/reminder_notifier.dart' show reminderTapTimeClock;
import 'tracking_config.dart';
import 'tracking_task_handler.dart';

/// The pieces of work-hours tracking that more than one isolate needs: the UI
/// (clock-in), the service itself, and the WATCHDOG alarm that restarts the
/// service when the phone stopped it (2026-11-13: shifts showed hours with no
/// location because phones closed ATLAS in the background).

// ---- the recording notice ------------------------------------------------------
//
// Android REQUIRES a visible notification while an app records location in the
// background; without one it treats the app as hidden and closes it. It is made
// as quiet as Android allows: its own MIN channel (a channel's importance is
// fixed once created, so this is a NEW id, not `work_location`), no sound, no
// badge, no time, hidden on the lock screen, and its text only changes when
// something is wrong.

const _channelId = 'work_shift_quiet';

void initTrackingForeground() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: _channelId,
      channelName: 'Work shift (recording)',
      channelDescription: 'A quiet notice while ATLAS records your work location between clock-in and clock-out.',
      channelImportance: NotificationChannelImportance.MIN,
      priority: NotificationPriority.MIN,
      onlyAlertOnce: true,
      visibility: NotificationVisibility.VISIBILITY_SECRET,
    ),
    iosNotificationOptions: const IOSNotificationOptions(showNotification: false, playSound: false),
    foregroundTaskOptions: ForegroundTaskOptions(
      // The service's minute tick: heartbeat, upload, the 16 h cap.
      eventAction: ForegroundTaskEventAction.repeat(60 * 1000),
      autoRunOnBoot: true,
      autoRunOnMyPackageReplaced: true,
      allowWakeLock: true,
      allowAutoRestart: true,
      stopWithTask: false,
    ),
  );
}

const trackingNoticeTitle = 'ATLAS · on shift';

String trackingNoticeText(DateTime since) => 'Since ${ManilaTime.time(since)}. Ends when you clock out.';

Future<ServiceRequestResult> startTrackingForeground(DateTime since) => FlutterForegroundTask.startService(
      serviceId: 4217,
      serviceTypes: const [ForegroundServiceTypes.location],
      notificationTitle: trackingNoticeTitle,
      notificationText: trackingNoticeText(since),
      callback: startTrackingCallback,
    );

// ---- "do something" alerts ---------------------------------------------------------
//
// A real notification (sound, heads-up) when the employee must act for recording
// to go on. Tapping it opens the Time Clock, which re-checks and restarts.

enum TrackingAlert {
  locationOff(7301, 'Turn your location back on', 'ATLAS cannot record your work location while Location is off. Swipe down and turn Location on.'),
  permissionLost(7302, 'ATLAS lost location permission', 'Tap to open ATLAS and allow location "All the time" so your shift is recorded.'),
  stopped(7303, 'ATLAS stopped recording your shift', 'Your phone closed ATLAS. Tap to open it and recording starts again.');

  final int id;
  final String title;
  final String body;
  const TrackingAlert(this.id, this.title, this.body);
}

class TrackingAlerts {
  static const channel = AndroidNotificationChannel(
    'tracking_alerts',
    'Work location problems',
    description: 'Tells you when something stops ATLAS from recording your shift, and what to do.',
    importance: Importance.high,
  );

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  TrackingAlerts([FlutterLocalNotificationsPlugin? plugin]) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  Future<void> _init() async {
    if (_ready) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_hris')),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
      _ready = true;
    } catch (e) {
      debugPrint('tracking: alerts init failed: $e');
    }
  }

  Future<void> show(TrackingAlert a) async {
    await _init();
    if (!_ready) return;
    try {
      await _plugin.show(
        id: a.id,
        title: a.title,
        body: a.body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            importance: channel.importance,
            priority: Priority.high,
            category: AndroidNotificationCategory.status,
            styleInformation: BigTextStyleInformation(a.body),
            color: const Color(0xFF0B5563),
            ticker: a.title,
          ),
        ),
        payload: reminderTapTimeClock,
      );
    } catch (e) {
      debugPrint('tracking: alert failed: $e');
    }
  }

  Future<void> clear(TrackingAlert a) async {
    await _init();
    if (!_ready) return;
    try {
      await _plugin.cancel(id: a.id);
    } catch (_) {}
  }

  Future<void> clearAll() async {
    for (final a in TrackingAlert.values) {
      await clear(a);
    }
  }
}

// ---- the watchdog -------------------------------------------------------------------
//
// Every 15 minutes during an open shift: is the recording service still alive?
// If the phone stopped it, start it again; if even that fails, tell the employee.
// The shift's config is the switch: no config = no shift = the watchdog cancels
// itself.

const trackingWatchdogAlarmId = 0x30000001;
const trackingWatchdogEvery = Duration(minutes: 15);

/// A start by the watchdog reads as "the phone closed the app" on the trail.
const watchdogRestartKey = 'tracking.restarted_by_watchdog';

Future<void> armTrackingWatchdog() async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await AndroidAlarmManager.periodic(
      trackingWatchdogEvery,
      trackingWatchdogAlarmId,
      trackingWatchdogCallback,
      exact: true,
      wakeup: true,
      allowWhileIdle: true,
      rescheduleOnReboot: true,
    );
  } catch (e) {
    debugPrint('tracking: watchdog not armed: $e');
  }
}

Future<void> disarmTrackingWatchdog() async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await AndroidAlarmManager.cancel(trackingWatchdogAlarmId);
  } catch (_) {}
}

@pragma('vm:entry-point')
Future<void> trackingWatchdogCallback() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  try {
    final config = await TrackingConfig.load();
    if (config == null) {
      await disarmTrackingWatchdog();
      return;
    }
    if (await FlutterForegroundTask.isRunningService) return;
    initTrackingForeground();
    await FlutterForegroundTask.saveData(key: watchdogRestartKey, value: true);
    final result = await startTrackingForeground(config.since);
    if (result is ServiceRequestFailure) {
      await FlutterForegroundTask.removeData(key: watchdogRestartKey);
      await TrackingAlerts().show(TrackingAlert.stopped);
    }
  } catch (e) {
    debugPrint('tracking: watchdog failed: $e');
    await TrackingAlerts().show(TrackingAlert.stopped);
  }
}
