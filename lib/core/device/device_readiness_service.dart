import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
// Prefixed for the same reason as the location gate service: permission_handler
// and geolocator both export a `ServiceStatus`.
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:shared_preferences/shared_preferences.dart';

/// The two phone settings that are not location but still decide whether
/// work-hours tracking survives a shift: the tracking NOTIFICATION (Android 13+
/// asks for it) and the BATTERY-OPTIMISATION exemption (without it, most phones
/// sold here stop a background app within minutes of the screen going off).
class DeviceReadiness {
  final bool notificationsGranted;
  final bool batteryUnrestricted;

  /// EXACT alarms (the clock-in / clock-out reminders, 2026-09-17). Android 13+
  /// grants them to the app outright (USE_EXACT_ALARM); Android 12 leaves it to
  /// a switch on the "Alarms & reminders" page, which no dialog can set — the
  /// app can only say where it is (see `oemExactAlarmHint`); older versions
  /// never ask.
  final bool exactAlarmsGranted;

  /// `Build.MANUFACTURER`, lower-cased; '' when unknown.
  final String manufacturer;

  const DeviceReadiness({
    required this.notificationsGranted,
    required this.batteryUnrestricted,
    this.exactAlarmsGranted = true,
    this.manufacturer = '',
  });

  static const ready = DeviceReadiness(notificationsGranted: true, batteryUnrestricted: true);
}

/// Abstract so the setup wizard can be tested with a scripted fake.
abstract class DeviceReadinessService {
  Future<DeviceReadiness> check();

  Future<void> requestNotifications();

  Future<void> requestBatteryExemption();

  Future<void> openAppSettings();

  /// Optional setup steps the employee chose to skip, by step name. Persisted,
  /// so a deliberate "Skip for now" is not asked again on every launch.
  Future<Set<String>> skippedSteps();

  Future<void> skipStep(String name);
}

class PlatformReadinessService implements DeviceReadinessService {
  PlatformReadinessService();

  static const _skippedKey = 'setup.skipped';

  String? _manufacturer;

  @override
  Future<DeviceReadiness> check() async {
    return DeviceReadiness(
      notificationsGranted: await _granted(ph.Permission.notification),
      batteryUnrestricted: await _granted(ph.Permission.ignoreBatteryOptimizations),
      exactAlarmsGranted: await _canScheduleExact(),
      manufacturer: await _readManufacturer(),
    );
  }

  Future<bool> _granted(ph.Permission permission) async {
    try {
      final status = await permission.status.timeout(const Duration(seconds: 5));
      return status.isGranted || status.isLimited;
    } catch (_) {
      // A host with no plugin, or a channel that refuses: these steps are
      // optional, so an unreadable state must never block the app.
      return true;
    }
  }

  static const _alarms = MethodChannel('hris/alarms');

  /// AlarmManager's own answer (MainActivity) — NOT permission_handler's
  /// `scheduleExactAlarm`, which reads the manifest's SCHEDULE_EXACT_ALARM entry
  /// and so reported "denied" on every Android 13+ phone, where this app runs on
  /// USE_EXACT_ALARM instead (a HONOR, 2026-09-18). Unknown counts as fine.
  Future<bool> _canScheduleExact() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      return await _alarms.invokeMethod<bool>('canScheduleExact').timeout(const Duration(seconds: 5)) ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<String> _readManufacturer() async {
    final cached = _manufacturer;
    if (cached != null) return cached;
    if (defaultTargetPlatform != TargetPlatform.android) return _manufacturer = '';
    try {
      final info = await DeviceInfoPlugin().androidInfo.timeout(const Duration(seconds: 5));
      return _manufacturer = info.manufacturer.toLowerCase();
    } catch (_) {
      return _manufacturer = '';
    }
  }

  @override
  Future<void> requestNotifications() async {
    try {
      // Timed out like every permission request in this app: a future that
      // never completes must not be able to strand the wizard.
      final status = await ph.Permission.notification.request().timeout(const Duration(seconds: 60));
      // Refused twice, Android stops showing the dialog; Settings still works.
      if (status.isPermanentlyDenied) await ph.openAppSettings();
    } catch (_) {
      // The wizard re-checks after every action and shows whatever is true.
    }
  }

  @override
  Future<void> requestBatteryExemption() async {
    try {
      // The system "Let app always run in background?" dialog. Needs
      // REQUEST_IGNORE_BATTERY_OPTIMIZATIONS in the manifest.
      await ph.Permission.ignoreBatteryOptimizations.request().timeout(const Duration(seconds: 60));
    } catch (_) {}
  }

  @override
  Future<void> openAppSettings() async {
    try {
      await ph.openAppSettings();
    } catch (_) {}
  }

  @override
  Future<Set<String>> skippedSteps() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_skippedKey) ?? const <String>[]).toSet();
  }

  @override
  Future<void> skipStep(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final skipped = (prefs.getStringList(_skippedKey) ?? const <String>[]).toSet()..add(name);
    await prefs.setStringList(_skippedKey, skipped.toList()..sort());
  }
}
