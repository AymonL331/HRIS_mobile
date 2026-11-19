import 'dart:async';
import 'dart:convert';

import '../../core/auth/session_controller.dart';
import '../../core/device/device_readiness_service.dart';
import '../../core/device/oem_hints.dart';
import '../../core/device/phone_state_service.dart';
import '../../core/http/endpoints.dart';
import '../../core/location/location_gate_service.dart';

/// WHAT STOPS A SHIFT FROM BEING RECORDED, AND THE ONE TAP THAT FIXES IT
/// (2026-11-13, widened 2026-11-19 after "Phone was silent").
///
/// At every clock-in the app re-reads everything recording needs. The first
/// thing wrong blocks the clock-in with plain words and a "Fix it" that opens the
/// EXACT page (or Android's own dialog) for that switch — not just the app page.
/// The same readings are reported to the server so HR can see them beside the
/// trail (server migration 125).

/// Where "Fix it" goes.
enum SetupFix {
  /// The phone's Location page (location is switched off).
  locationSettings,

  /// ATLAS's page in Settings (permissions, "Restricted").
  appSettings,

  /// Android's notification dialog (Settings when it will not ask again).
  notifications,

  /// Android's own "Let app always run in background?" dialog.
  batteryExemption,

  /// The Battery Saver page.
  batterySaver,
}

class SetupProblem {
  final String message;
  final SetupFix fix;

  /// This maker adds its own Autostart switch that no API reports — offer the
  /// button that opens it (Xiaomi, OPPO/realme, vivo, HUAWEI/HONOR, Infinix).
  final bool offerAutostart;

  const SetupProblem(this.message, this.fix, {this.offerAutostart = false});
}

/// Brands whose own Autostart / app-launch page decides whether ATLAS survives.
bool hasAutostartPage(String manufacturer) {
  final hint = oemBatteryHint(manufacturer);
  return hint != null && hint.brand != 'Samsung';
}

/// THE CLOCK-IN CHECK. Null = ready; otherwise the first thing to fix, in order:
/// location, notifications, then everything that lets the phone stop ATLAS.
/// Data Saver does NOT block: points are still recorded and queued, they only
/// arrive late (it is reported to HR instead).
Future<SetupProblem?> trackingReadinessProblem({
  required LocationGateService gate,
  required DeviceReadinessService device,
  PhoneStateService? phone,
}) async {
  final GateVerdict verdict;
  final DeviceReadiness d;
  try {
    verdict = await gate.check();
    d = await device.check();
  } catch (_) {
    return null; // unreadable: never block a clock-in on a check that failed
  }
  switch (verdict) {
    case GateVerdict.serviceOff:
      return const SetupProblem('Location is turned off. Turn it on, then clock in.', SetupFix.locationSettings);
    case GateVerdict.permissionDenied:
    case GateVerdict.permissionDeniedForever:
      return const SetupProblem('ATLAS is not allowed to use your location. Allow it, then clock in.', SetupFix.appSettings);
    case GateVerdict.backgroundDenied:
      return const SetupProblem('Location must be set to "Allow all the time" so your shift is recorded.', SetupFix.appSettings);
    case GateVerdict.reducedAccuracy:
      return const SetupProblem('Turn on "Use precise location" for ATLAS, then clock in.', SetupFix.appSettings);
    case GateVerdict.ok:
      break;
  }
  if (!d.notificationsGranted) {
    return const SetupProblem('Allow ATLAS notifications so it can tell you when recording stops.', SetupFix.notifications);
  }
  final autostart = hasAutostartPage(d.manufacturer);
  if (!d.batteryUnrestricted) {
    return SetupProblem(
      'Set ATLAS battery use to "Unrestricted" (no battery saving) so your phone does not close it during your shift.',
      SetupFix.batteryExemption,
      offerAutostart: autostart,
    );
  }
  final PhoneState p;
  try {
    p = phone == null ? PhoneState.unknown : await phone.read();
  } catch (_) {
    return null;
  }
  if (p.backgroundRestricted == true) {
    return SetupProblem(
      'ATLAS is set to "Restricted" in your phone\'s battery settings, so the phone stops it. Open Battery and choose "Unrestricted", then clock in.',
      SetupFix.appSettings,
      offerAutostart: autostart,
    );
  }
  if (p.powerSaveBlocksLocation == true) {
    return const SetupProblem(
      'Battery Saver turns your location off when the screen is off, so your shift would not be recorded. Turn Battery Saver off, then clock in.',
      SetupFix.batterySaver,
    );
  }
  return null;
}

/// Open whatever fixes [fix]. Every opener swallows its own failures: the next
/// clock-in re-checks and shows whatever is true.
Future<void> applySetupFix(
  SetupFix fix, {
  LocationGateService? gate,
  DeviceReadinessService? device,
  PhoneStateService? phone,
}) async {
  try {
    switch (fix) {
      case SetupFix.locationSettings:
        await gate?.openLocationSettings();
      case SetupFix.appSettings:
        await device?.openAppSettings();
      case SetupFix.notifications:
        await device?.requestNotifications();
      case SetupFix.batteryExemption:
        await device?.requestBatteryExemption();
      case SetupFix.batterySaver:
        if (phone != null) {
          await phone.openBatterySaver();
        } else {
          await device?.openAppSettings();
        }
    }
  } catch (_) {}
}

// ---- reporting to HR (server migration 125) ------------------------------------

abstract class PhoneSettingsApi {
  Future<void> send(Map<String, dynamic> body);
}

class MobilePhoneSettingsApi implements PhoneSettingsApi {
  final SessionController session;
  const MobilePhoneSettingsApi(this.session);

  @override
  Future<void> send(Map<String, dynamic> body) =>
      session.guard(() => session.client.post(Endpoints.trackingPhoneSettings, body: body));
}

/// Sends the phone's settings to the server: when the app opens, whenever it
/// comes back to the screen, and at every clock-in. The same settings are not
/// re-sent within [resendAfter] unless forced; a failed send is simply retried
/// next time. Never throws, never blocks anything.
class PhoneSettingsReporter {
  final PhoneSettingsApi api;
  final LocationGateService? gate;
  final DeviceReadinessService? device;
  final PhoneStateService? phone;
  final Duration resendAfter;
  final DateTime Function() _now;

  String? _lastBody;
  DateTime? _lastAt;
  bool _sending = false;

  PhoneSettingsReporter({
    required this.api,
    this.gate,
    this.device,
    this.phone,
    this.resendAfter = const Duration(minutes: 30),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// What the server stores. Null for a setting this phone could not read.
  Future<Map<String, dynamic>> collect() async {
    bool? locationOk;
    DeviceReadiness? d;
    var p = PhoneState.unknown;
    try {
      if (gate != null) locationOk = await gate!.check() == GateVerdict.ok;
    } catch (_) {}
    try {
      d = await device?.check();
    } catch (_) {}
    try {
      if (phone != null) p = await phone!.read();
    } catch (_) {}
    return {
      'location_ok': locationOk,
      'notifications_allowed': d?.notificationsGranted,
      'battery_unrestricted': d?.batteryUnrestricted,
      'background_restricted': p.backgroundRestricted,
      'power_saver_on': p.powerSaveOn,
      'power_saver_blocks_location': p.powerSaveBlocksLocation,
      'data_saver_on': p.dataSaverOn,
      'manufacturer': (d?.manufacturer ?? '').isEmpty ? null : d!.manufacturer,
      'model': p.model,
      'os_version': p.osVersion,
    };
  }

  Future<void> report({bool force = false}) async {
    if (_sending) return;
    _sending = true;
    try {
      final body = await collect();
      final key = jsonEncode(body);
      final last = _lastAt;
      if (!force && key == _lastBody && last != null && _now().difference(last) < resendAfter) return;
      await api.send(body);
      _lastBody = key;
      _lastAt = _now();
    } catch (_) {
      // Offline, signed out, an older server without the endpoint: next time.
    } finally {
      _sending = false;
    }
  }
}
