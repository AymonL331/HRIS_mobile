import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hris_mobile/core/device/capture_context.dart';
import 'package:hris_mobile/core/location/location_fix.dart';

/// Where + on what phone a profile photo / face enrollment was taken (server
/// migration 134). Evidence only: never throws, the photo always goes.
class _Fixes implements LocationFixService {
  final Object? error;
  Duration? asked;
  _Fixes({this.error});

  @override
  Future<LocationFix> acquire({Duration timeLimit = const Duration(seconds: 15)}) async {
    asked = timeLimit;
    if (error != null) throw error!;
    return LocationFix(
      latitude: 14.5513,
      longitude: 121.0176,
      accuracyM: 12.5,
      isMocked: false,
      at: DateTime.utc(2026, 11, 26, 1, 2, 3),
      gpsTime: DateTime.utc(2026, 11, 26, 1, 2, 2),
    );
  }
}

Future<Map<String, dynamic>> _vivo() async =>
    {'platform': 'android', 'brand': 'vivo', 'model': 'vivo 1906', 'os_version': 'Android 9'};

void main() {
  test('a fix + the phone: position (GPS time), brand, model and Android version', () async {
    final fixes = _Fixes();
    final c = await CaptureContextCollector(fixes: fixes, readDevice: _vivo).collect();
    expect(c['location'], {
      'status': 'ok',
      'latitude': 14.5513,
      'longitude': 121.0176,
      'accuracy': 12.5,
      'taken_at': '2026-11-26T01:02:02.000Z',
      'mocked': false,
    });
    expect(c['device'], {'platform': 'android', 'brand': 'vivo', 'model': 'vivo 1906', 'os_version': 'Android 9'});
    expect(fixes.asked, const Duration(seconds: 10));
  });

  test('no fix in time -> unavailable; permission refused -> denied; the device still comes', () async {
    final late = await CaptureContextCollector(fixes: _Fixes(error: const FixTimeout()), readDevice: _vivo).collect();
    expect(late['location'], {'status': 'unavailable'});
    expect((late['device'] as Map)['model'], 'vivo 1906');
    final refused = await CaptureContextCollector(
      fixes: _Fixes(error: const PermissionDeniedException('no')),
      readDevice: _vivo,
    ).collect();
    expect(refused['location'], {'status': 'denied'});
  });

  test('a device read that fails still names the platform, never throws', () async {
    final c = await CaptureContextCollector(fixes: _Fixes(), readDevice: () async => throw StateError('x')).collect();
    expect((c['device'] as Map)['platform'], isNotNull);
  });
}
