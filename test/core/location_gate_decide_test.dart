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

  test('WHILE-IN-USE is never enough, at any accuracy (2026-09-14)', () {
    // The headline rule. "While using the app" and "Only this time" both land
    // here, and neither may run the app — it has to keep working when closed.
    for (final a in LocationAccuracyStatus.values) {
      expect(d(true, LocationPermission.whileInUse, a), GateVerdict.backgroundDenied, reason: '$a');
    }
  });

  test('with Always, Approximate is refused and precise/unknown pass', () {
    expect(d(true, LocationPermission.always, LocationAccuracyStatus.reduced), GateVerdict.reducedAccuracy);
    expect(d(true, LocationPermission.always, LocationAccuracyStatus.precise), GateVerdict.ok);
    // `unknown` only arises pre-Android-12 or when the platform call throws;
    // deliberately lenient, and pinned so nobody "tightens" it by accident.
    expect(d(true, LocationPermission.always, LocationAccuracyStatus.unknown), GateVerdict.ok);
  });

  test('a missing grant is reported before accuracy, whatever the accuracy', () {
    for (final a in LocationAccuracyStatus.values) {
      expect(d(true, LocationPermission.denied, a), GateVerdict.permissionDenied, reason: '$a');
      expect(d(true, LocationPermission.deniedForever, a), GateVerdict.permissionDeniedForever, reason: '$a');
    }
  });

  test('across the WHOLE matrix, only Always + precise/unknown passes', () {
    var okCells = 0;
    for (final on in [true, false]) {
      for (final p in LocationPermission.values) {
        for (final a in LocationAccuracyStatus.values) {
          final v = d(on, p, a);
          final shouldPass = on &&
              p == LocationPermission.always &&
              a != LocationAccuracyStatus.reduced;
          expect(v == GateVerdict.ok, shouldPass, reason: 'service=$on permission=$p accuracy=$a -> $v');
          if (v == GateVerdict.ok) okCells += 1;
        }
      }
    }
    // Always × {precise, unknown}, service on.
    expect(okCells, 2);
  });

  test('only ok does not block', () {
    for (final v in GateVerdict.values) {
      expect(v.blocks, v != GateVerdict.ok);
    }
  });
}
