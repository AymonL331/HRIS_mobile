import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/features/time_clock/clock_models.dart';
import 'package:hris_mobile/features/tracking/tracking_models.dart';

import '../fakes/clock_fakes.dart';

void main() {
  test('an older server with no tracking block means nothing is recorded', () {
    expect(TrackingState.fromJson(null).active, isFalse);
    expect(ClockStatus.fromJson(statusJson()).tracking.active, isFalse);
  });

  test('active needs a shift id; the policy is read from the server with defaults', () {
    expect(TrackingState.fromJson({'active': true, 'attendance_log_id': null}).active, isFalse);
    final s = ClockStatus.fromJson(statusJson(tracking: trackingJson(attendanceLogId: 42))).tracking;
    expect(s.active, isTrue);
    expect(s.attendanceLogId, 42);
    expect(s.since, DateTime.utc(2026, 9, 11, 0, 13));
    expect(s.policy.distanceFilterM, 25);
    expect(s.policy.heartbeatS, 300);
    final partial = TrackingPolicy.fromJson({'heartbeat_s': 120});
    expect(partial.heartbeatS, 120);
    expect(partial.minIntervalS, 30);
  });

  test('point ids are v4 UUIDs the server accepts, and unique', () {
    final re = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
    final seen = <String>{};
    final r = Random(7);
    for (var i = 0; i < 1000; i++) {
      final u = newPingUuid(r);
      expect(re.hasMatch(u), isTrue, reason: u);
      seen.add(u);
    }
    expect(seen.length, 1000);
  });

  test('a point survives the queue row round trip; unknown sensor values are omitted from the upload', () {
    final p = QueuedPing(
      uuid: newPingUuid(),
      attendanceLogId: 9,
      kind: 'heartbeat',
      capturedAt: DateTime.utc(2026, 9, 14, 3, 4, 5),
      latitude: 14.1,
      longitude: 121.2,
      accuracyM: 12.5,
      speedMps: -1,
      headingDeg: double.nan,
      isMocked: true,
      batteryPct: 55,
    );
    final back = QueuedPing.fromRow(p.toRow());
    expect(back.uuid, p.uuid);
    expect(back.capturedAtUtc, p.capturedAtUtc);
    expect(back.isMocked, isTrue);
    expect(back.batteryPct, 55);
    final json = back.toJson();
    expect(json.containsKey('speed_mps'), isFalse);
    expect(json.containsKey('heading_deg'), isFalse);
    expect(json['accuracy_m'], 12.5);
    expect(json['is_mocked'], true);

    final gap = QueuedPing(uuid: newPingUuid(), attendanceLogId: 9, kind: 'gap_location_off', capturedAt: DateTime.utc(2026));
    expect(gap.hasFix, isFalse);
    expect(gap.toJson().containsKey('latitude'), isFalse);
  });
}
