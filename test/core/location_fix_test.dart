import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/location/geo.dart';
import 'package:hris_mobile/core/location/location_fix.dart';

LocationFix fix({double acc = 10, bool mocked = false}) =>
    LocationFix(latitude: 14.5995, longitude: 120.9842, accuracyM: acc, isMocked: mocked, at: DateTime.now());

void main() {
  test('a mocked position is refused whatever its accuracy', () {
    expect(validateFix(fix(acc: 3, mocked: true)), isA<FixMocked>());
  });

  test('accuracy thresholds: fine → ok, >100 m → ok with warning, >500 m → refused', () {
    expect(validateFix(fix(acc: 12)), isA<FixOk>().having((o) => o.warnLowAccuracy, 'warn', false));
    expect(validateFix(fix(acc: 100)), isA<FixOk>().having((o) => o.warnLowAccuracy, 'warn', false));
    expect(validateFix(fix(acc: 101)), isA<FixOk>().having((o) => o.warnLowAccuracy, 'warn', true));
    expect(validateFix(fix(acc: 500)), isA<FixOk>().having((o) => o.warnLowAccuracy, 'warn', true));
    expect(validateFix(fix(acc: 501)), isA<FixTooCoarse>().having((o) => o.accuracyM, 'm', 501));
  });

  test('haversine agrees with the server on a known pair', () {
    // Manila City Hall-ish → Makati worksite used by the sandbox: ~6.7 km.
    final d = haversineMeters(14.5995, 120.9842, 14.5513714, 121.0175541);
    expect(d, closeTo(6470, 150));
    expect(haversineMeters(1, 1, 1, 1), 0);
  });

  test('toJson is the server body shape', () {
    expect(fix(acc: 7.5).toJson(), {'latitude': 14.5995, 'longitude': 120.9842, 'accuracy': 7.5});
  });
}
