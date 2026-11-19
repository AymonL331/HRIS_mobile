import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// PHONE SETTINGS THAT CAN STOP RECORDING (2026-11-19), beyond the battery
/// exemption `DeviceReadinessService` already reads. Each one has an Android
/// API, so the app can SEE it and send the employee straight to the switch:
///
///  - `backgroundRestricted` — "Restricted" in the app's battery page (Android
///    9+): the phone stops ATLAS in the background whatever else is allowed.
///  - Battery Saver, and whether it turns location off (or limits it) while the
///    screen is off (`locationPowerSaveMode`, Android 9+). With the screen off is
///    exactly when a shift is recorded.
///  - Data Saver blocking ATLAS's background data: points are still recorded and
///    queued, but reach the server only when the app is opened.
///
/// Null everywhere = the phone could not tell (older Android, no channel in a
/// test). Unknown is treated as fine: a warning that might be wrong is worse
/// than none.
class PhoneState {
  final bool? backgroundRestricted;
  final bool? powerSaveOn;

  /// Battery Saver is on AND set to turn location off / foreground-only while the
  /// screen is off. Null when Battery Saver is on but the mode is unreadable.
  final bool? powerSaveBlocksLocation;
  final bool? dataSaverOn;
  final String? model;
  final String? osVersion;

  const PhoneState({
    this.backgroundRestricted,
    this.powerSaveOn,
    this.powerSaveBlocksLocation,
    this.dataSaverOn,
    this.model,
    this.osVersion,
  });

  static const unknown = PhoneState();

  /// Android's PowerManager.LOCATION_MODE_*: 1 GPS off with the screen off,
  /// 2 all location off with the screen off, 3 foreground apps only. 0 (no
  /// change) and 4 (requests throttled) leave a shift's recording alone.
  static bool? blocksLocation({required bool? powerSaveOn, required int? locationPowerSaveMode}) {
    if (powerSaveOn == null) return null;
    if (!powerSaveOn) return false;
    if (locationPowerSaveMode == null) return null;
    return const {1, 2, 3}.contains(locationPowerSaveMode);
  }

  factory PhoneState.fromChannel(Map<Object?, Object?> m) {
    bool? b(String k) => m[k] is bool ? m[k] as bool : null;
    String? s(String k) => m[k] is String && (m[k] as String).isNotEmpty ? m[k] as String : null;
    final powerSave = b('powerSaveOn');
    final mode = m['locationPowerSaveMode'] is int ? m['locationPowerSaveMode'] as int : null;
    return PhoneState(
      backgroundRestricted: b('backgroundRestricted'),
      powerSaveOn: powerSave,
      powerSaveBlocksLocation: blocksLocation(powerSaveOn: powerSave, locationPowerSaveMode: mode),
      dataSaverOn: b('dataSaverOn'),
      model: s('model'),
      osVersion: s('osVersion'),
    );
  }
}

/// Abstract so tests can script it; optional in the widget tree (absent = unknown).
abstract class PhoneStateService {
  Future<PhoneState> read();

  /// Android's Battery Saver page.
  Future<void> openBatterySaver();

  /// ATLAS's "background data" switch (Data Saver), or its app page.
  Future<void> openDataSaver();

  /// The maker's own Autostart / app-launch page (Xiaomi, OPPO/realme, vivo,
  /// HUAWEI/HONOR, Infinix/TECNO, Samsung). False = no such page on this phone.
  Future<bool> openAutostart();
}

class PlatformPhoneStateService implements PhoneStateService {
  const PlatformPhoneStateService();

  static const _channel = MethodChannel('hris/phone_state');

  bool get _android => defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<PhoneState> read() async {
    if (!_android) return PhoneState.unknown;
    try {
      final m = await _channel.invokeMethod<Map<Object?, Object?>>('read').timeout(const Duration(seconds: 5));
      return m == null ? PhoneState.unknown : PhoneState.fromChannel(m);
    } catch (_) {
      return PhoneState.unknown;
    }
  }

  Future<bool> _call(String method) async {
    if (!_android) return false;
    try {
      return await _channel.invokeMethod<bool>(method).timeout(const Duration(seconds: 5)) ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> openBatterySaver() => _call('openBatterySaver');

  @override
  Future<void> openDataSaver() => _call('openDataSaver');

  @override
  Future<bool> openAutostart() => _call('openAutostart');
}
