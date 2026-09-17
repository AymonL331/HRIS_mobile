import 'dart:async';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/auth/session_controller.dart';
import 'core/auth/session_store.dart';
import 'core/config/env_store.dart';
import 'core/device/device_readiness_service.dart';
import 'core/location/location_fix.dart';
import 'core/location/location_gate_service.dart';
import 'features/app_update/app_update_api.dart';
import 'features/app_update/app_update_controller.dart';
import 'features/app_update/app_update_models.dart';
import 'features/attendance/attendance_api.dart';
import 'features/payslips/payslip_api.dart';
import 'features/reminders/reminder_coordinator.dart';
import 'features/reminders/reminder_notifier.dart';
import 'features/reminders/reminder_scheduler.dart';
import 'features/reminders/reminder_store.dart';
import 'features/reminders/reminder_tap_relay.dart';
import 'features/reminders/reminders_api.dart';
import 'features/time_clock/clock_api.dart';
import 'features/tracking/tracking_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final envStore = EnvStore();
  await envStore.load();

  String version = '0.0.0';
  try {
    final info = await PackageInfo.fromPlatform();
    version = '${info.version}+${info.buildNumber}';
  } catch (_) {
    // A missing platform channel (tests, odd hosts) must not stop the app.
  }

  final session = SessionController(env: envStore, store: SecureSessionStore(), appVersion: version);

  // In-app update (2026-09-15): asks the SELECTED server for a newer published APK.
  final appUpdate = AppUpdateController(
    env: envStore,
    currentVersionCode: versionCodeOf(version),
    currentVersionName: version.split('+').first,
    apiFor: (baseUrl) => HttpAppUpdateApi(baseUrl: baseUrl, appVersion: version),
  );

  // Work-hours location tracking: the port the service talks back on, then the
  // UI-side driver. A REAL sign-out (token gone) or an environment switch ends
  // recording; an offline cold start that merely shows the login screen does not.
  FlutterForegroundTask.initCommunicationPort();
  final tracking = ForegroundTrackingService(session);

  // Clock-in / clock-out reminders (2026-09-17): the alarms that wake the phone
  // at HR's reminder times, the notification they show, and the relay a tap
  // lands on. The alarm manager must be initialised before an alarm is armed;
  // the notifier before anything is shown — both once, here.
  final reminderStore = PrefsReminderStore();
  final reminderTaps = ReminderTapRelay();
  final reminderNotifier = LocalReminderNotifier(store: reminderStore);
  final reminders = ReminderCoordinator(
    session: session,
    store: reminderStore,
    scheduler: ReminderScheduler(
      store: reminderStore,
      alarms: const AndroidAlarmPort(),
      api: MobileReminderScheduleApi(session),
    ),
  );
  try {
    await AndroidAlarmManager.initialize();
  } catch (_) {
    // A host with no alarm manager (tests, odd devices): the bell still works.
  }
  await reminderNotifier.initialize(onTap: (payload) => reminderTaps.value = payload);

  session.addListener(() {
    if (session.state is SignedOut && !session.hasStoredSession) {
      unawaited(tracking.stop(reason: 'signed_out'));
      // Nothing may fire for an account that is gone.
      unawaited(reminders.clear());
    }
  });

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<EnvStore>.value(value: envStore),
        ChangeNotifierProvider<SessionController>.value(value: session),
        ChangeNotifierProvider<AppUpdateController>.value(value: appUpdate),
        // Not const: the gate has to REMEMBER that Android refused to ask again,
        // because `checkPermission()` cannot report `deniedForever` and a passive
        // re-check would otherwise downgrade it back to a dead "Try again".
        Provider<LocationGateService>.value(value: GeolocatorGateService()),
        // Notifications + battery exemption, the setup wizard's optional steps.
        Provider<DeviceReadinessService>.value(value: PlatformReadinessService()),
        Provider<TrackingService>.value(value: tracking),
        Provider<LocationFixService>.value(value: const GeolocatorFixService()),
        // The Time Clock's API is built from the session by the shell; tests
        // inject a fake here instead.
        Provider<ClockApi?>.value(value: null),
        Provider<AttendanceApi?>.value(value: null),
        Provider<PayslipApi?>.value(value: null),
        Provider<NotificationsApi?>.value(value: null),
        // The reminders, as the shell, the Time Clock and Settings read them.
        Provider<ReminderSync?>.value(value: reminders),
        Provider<ReminderCoordinator?>.value(value: reminders),
        Provider<ReminderNotifier?>.value(value: reminderNotifier),
        ChangeNotifierProvider<ReminderTapRelay>.value(value: reminderTaps),
      ],
      child: const HrisApp(),
    ),
  );

  // After the first frame so the splash is what the user sees while the stored
  // token is validated.
  session.bootstrap();
}
