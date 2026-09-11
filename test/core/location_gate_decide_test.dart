import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hris_mobile/core/location/location_gate_service.dart';

void main() {
  GateVerdict d(bool on, LocationPermission p, LocationAccuracyStatus a) =>
      decideGate(serviceEnabled: on, permission: p, accuracy: a);

  test('service off wins over everything', () {
    expect(d(false, LocationPermission.always, LocationAccuracyStatus.precise), GateVerdict.serviceOff);
    expect(d(false, LocationPermission.denied, LocationAccuracyStatus.unknown), GateVerdict.serviceOff);
  });

  test('permission states', () {
    expect(d(true, LocationPermission.denied, LocationAccuracyStatus.unknown), GateVerdict.permissionDenied);
    expect(d(true, LocationPermission.unableToDetermine, LocationAccuracyStatus.unknown), GateVerdict.permissionDenied);
    expect(d(true, LocationPermission.deniedForever, LocationAccuracyStatus.unknown), GateVerdict.permissionDeniedForever);
  });

  test('granted but Approximate is refused; precise or unknown-with-grant passes', () {
    expect(d(true, LocationPermission.whileInUse, LocationAccuracyStatus.reduced), GateVerdict.reducedAccuracy);
    expect(d(true, LocationPermission.always, LocationAccuracyStatus.reduced), GateVerdict.reducedAccuracy);
    expect(d(true, LocationPermission.whileInUse, LocationAccuracyStatus.precise), GateVerdict.ok);
    expect(d(true, LocationPermission.always, LocationAccuracyStatus.precise), GateVerdict.ok);
    expect(d(true, LocationPermission.whileInUse, LocationAccuracyStatus.unknown), GateVerdict.ok);
  });

  test('only ok does not block', () {
    for (final v in GateVerdict.values) {
      expect(v.blocks, v != GateVerdict.ok);
    }
  });
}
