import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../location/location_fix.dart';

/// WHERE AND ON WHAT a profile photo / face enrollment was taken (server
/// migration 134, user 2026-11-26): "add the location and the map where the
/// profile photo and the face enrollment was took photo on ... track what is the
/// brand of the unit they use".
///
/// Sent beside the photo as `capture: { location, device }`. Evidence only — the
/// server never refuses a photo over it — so [collect] NEVER throws: no fix in
/// time is `unavailable`, a refused permission is `denied`, and the photo goes.
class CaptureContextCollector {
  final LocationFixService fixes;
  final Future<Map<String, dynamic>> Function() readDevice;
  final Duration timeLimit;

  CaptureContextCollector({
    LocationFixService? fixes,
    Future<Map<String, dynamic>> Function()? readDevice,
    this.timeLimit = const Duration(seconds: 10),
  })  : fixes = fixes ?? const GeolocatorFixService(),
        readDevice = readDevice ?? readAndroidDevice;

  Future<Map<String, dynamic>> collect() async {
    final results = await Future.wait([_location(), _device()]);
    return {'location': results[0], 'device': results[1]};
  }

  Future<Map<String, dynamic>> _location() async {
    try {
      final f = await fixes.acquire(timeLimit: timeLimit);
      return {
        'status': 'ok',
        'latitude': f.latitude,
        'longitude': f.longitude,
        'accuracy': f.accuracyM,
        'taken_at': (f.gpsTime ?? f.at.toUtc()).toUtc().toIso8601String(),
        'mocked': f.isMocked,
      };
    } on PermissionDeniedException {
      return {'status': 'denied'};
    } catch (_) {
      return {'status': 'unavailable'};
    }
  }

  Future<Map<String, dynamic>> _device() async {
    try {
      return await readDevice();
    } catch (_) {
      return {'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android'};
    }
  }
}

/// The phone itself: brand, model and Android version as the phone reports them
/// ("vivo" · "vivo 1906" · "Android 9").
Future<Map<String, dynamic>> readAndroidDevice() async {
  if (defaultTargetPlatform != TargetPlatform.android) {
    return {'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'other'};
  }
  final info = await DeviceInfoPlugin().androidInfo.timeout(const Duration(seconds: 5));
  final brand = info.manufacturer.trim().isNotEmpty ? info.manufacturer.trim() : info.brand.trim();
  return {
    'platform': 'android',
    if (brand.isNotEmpty) 'brand': brand,
    if (info.model.trim().isNotEmpty) 'model': info.model.trim(),
    'os_version': 'Android ${info.version.release}',
  };
}
