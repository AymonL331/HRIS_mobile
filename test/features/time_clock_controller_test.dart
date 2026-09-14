import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/http/api_exception.dart';
import 'package:hris_mobile/core/location/location_fix.dart';
import 'package:hris_mobile/features/time_clock/time_clock_controller.dart';

import '../fakes/clock_fakes.dart';

void main() {
  late FakeClockApi api;
  late FakeFixService fixes;
  late FakeFaceCapturer face;
  late TimeClockController c;

  setUp(() {
    api = FakeClockApi();
    fixes = FakeFixService();
    face = FakeFaceCapturer();
    c = TimeClockController(api: api, fixes: fixes);
  });

  test('load fills the status, syncs the clock, and computes the button rules', () async {
    await c.load();
    expect(c.status!.employeeName, 'Sofia Sandbox');
    expect(c.status!.canClockIn, isTrue);
    expect(c.status!.canClockOut, isFalse);
    expect(c.clock.synced, isTrue);
  });

  test('a punch takes a fresh fix, sends it, and refreshes today', () async {
    await c.load();
    await c.punch('in', capture: face.call);
    expect(fixes.acquired, 1);
    // The geotag AND the face payload travelled together.
    expect(api.punches.single, {
      'direction': 'in', 'latitude': 14.5515, 'longitude': 121.0177, 'accuracy': 9,
      'nonce': 'a' * 64,
      'embedding': isA<List<double>>(),
      'liveness_passed': true,
      'completed_challenges': const ['blink', 'turn_head'],
      'model_version': 'human-3',
    });
    expect(face.calls, ['in']);
    expect(c.outcome, isA<PunchSuccess>().having((o) => o.response.within, 'within', true));
    expect(c.status!.canClockIn, isFalse);
    expect(c.status!.canClockOut, isTrue);
    expect(c.phase, ClockPhase.idle);
  });

  test('a mocked fix is refused on the phone — nothing is sent', () async {
    await c.load();
    fixes.next = LocationFix(latitude: 1, longitude: 1, accuracyM: 5, isMocked: true, at: DateTime.now());
    await c.punch('in', capture: face.call);
    expect(api.punches, isEmpty);
    expect(c.outcome, isA<PunchFailure>().having((o) => o.message, 'message', contains('Mock location')));
  });

  test('a too-coarse fix is refused; a merely coarse one goes through with the warning', () async {
    await c.load();
    fixes.next = LocationFix(latitude: 1, longitude: 1, accuracyM: 900, isMocked: false, at: DateTime.now());
    await c.punch('in', capture: face.call);
    expect(api.punches, isEmpty);
    expect(c.outcome, isA<PunchFailure>().having((o) => o.message, 'message', contains('too imprecise')));

    fixes.next = LocationFix(latitude: 1, longitude: 1, accuracyM: 150, isMocked: false, at: DateTime.now());
    await c.punch('in', capture: face.call);
    expect(api.punches.length, 1);
    expect(c.outcome, isA<PunchSuccess>().having((o) => o.warnLowAccuracy, 'warn', true));
  });

  test('a GPS timeout is a failure with advice', () async {
    await c.load();
    fixes.timeout = true;
    await c.punch('in', capture: face.call);
    expect(api.punches, isEmpty);
    expect(c.outcome, isA<PunchFailure>().having((o) => o.message, 'message', contains('15 seconds')));
  });

  test('server outcomes: 409 → info + reload, geofence 422 → blocked, consent 422 → needs consent', () async {
    await c.load();
    api.punchError = const ApiException(status: 409, message: 'Already clocked in for today.');
    await c.punch('in', capture: face.call);
    expect(c.outcome, isA<PunchInfo>());

    api.punchError = const ApiException(status: 422, message: 'You appear to be outside the allowed worksite area — clock blocked.', fieldErrors: {'location': 'Outside the allowed worksite radius (~6470 m away).'});
    await c.punch('in', capture: face.call);
    expect(c.outcome, isA<PunchBlocked>());

    api.punchError = const ApiException(status: 422, message: 'Location consent is required.', fieldErrors: {'location_consent': 'x'});
    await c.punch('in', capture: face.call);
    expect(c.outcome, isA<PunchNeedsConsent>());
  });

  test('consent: status without consent → grantConsent → reloaded with consent', () async {
    api.status_ = statusJson(mobileConsent: false);
    await c.load();
    expect(c.status!.consentGiven, isFalse);
    await c.grantConsent();
    expect(api.consents, 1);
    expect(c.status!.consentGiven, isTrue);
  });

  test('range check measures the last fix against the worksite and sends nothing', () async {
    await c.load();
    await c.checkRange();
    expect(api.punches, isEmpty);
    expect(c.range.within, isTrue);
    expect(c.range.distanceM, lessThan(30));
  });
}
