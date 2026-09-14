import 'dart:math';

import '../../core/time/manila_time.dart';

int? _int(Object? v) => v == null ? null : (v is int ? v : int.tryParse('$v'));
double? _num(Object? v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

/// How densely to record, as the SERVER says (the `tracking.policy` block on
/// `/api/me/mobile-clock/status`). Served rather than compiled in so tuning the
/// trail needs a server restart, not a new APK in every employee's hands.
class TrackingPolicy {
  final int distanceFilterM;
  final int minIntervalS;
  final int heartbeatS;
  final int maxShiftHours;

  const TrackingPolicy({
    this.distanceFilterM = 25,
    this.minIntervalS = 30,
    this.heartbeatS = 300,
    this.maxShiftHours = 16,
  });

  factory TrackingPolicy.fromJson(Map<String, dynamic>? j) {
    const d = TrackingPolicy();
    if (j == null) return d;
    return TrackingPolicy(
      distanceFilterM: _int(j['distance_filter_m']) ?? d.distanceFilterM,
      minIntervalS: _int(j['min_interval_s']) ?? d.minIntervalS,
      heartbeatS: _int(j['heartbeat_s']) ?? d.heartbeatS,
      maxShiftHours: _int(j['max_shift_hours']) ?? d.maxShiftHours,
    );
  }

  Map<String, dynamic> toJson() => {
        'distance_filter_m': distanceFilterM,
        'min_interval_s': minIntervalS,
        'heartbeat_s': heartbeatS,
        'max_shift_hours': maxShiftHours,
      };
}

/// Should this phone be recording right now, and for which shift?
///
/// Decided by the server from the employee's OPEN shift (clocked in, not out,
/// within the cap) and their mobile consent — never by the phone's own idea of
/// "today", because attendance rows are keyed on the UTC date.
class TrackingState {
  final bool active;
  final int? attendanceLogId;
  final DateTime? since;
  final TrackingPolicy policy;

  const TrackingState({
    required this.active,
    required this.attendanceLogId,
    required this.since,
    this.policy = const TrackingPolicy(),
  });

  static const inactive = TrackingState(active: false, attendanceLogId: null, since: null);

  /// A server that predates tracking sends no block: nothing is recorded.
  factory TrackingState.fromJson(Map<String, dynamic>? j) {
    if (j == null) return inactive;
    final id = _int(j['attendance_log_id']);
    return TrackingState(
      active: j['active'] == true && id != null,
      attendanceLogId: id,
      since: ManilaTime.parseUtc(j['since'] as String?),
      policy: TrackingPolicy.fromJson(j['policy'] as Map<String, dynamic>?),
    );
  }
}

/// A random v4 UUID. The server de-duplicates re-sent points by it, so it must
/// be unique per point for the life of the queue — `Random.secure` is plenty.
String newPingUuid([Random? random]) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String hex(int from, int to) => b.sublist(from, to).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

/// One recorded point (or phone event) waiting in the offline queue.
///
/// `kind` matches the server's ENUM: `ping` (moved), `heartbeat` (still, on a
/// timer), and the events that explain a gap in the trail — `start`, `stop`,
/// `gap_location_off`, `gap_permission_lost`, `resumed_after_kill`.
class QueuedPing {
  final String uuid;
  final int attendanceLogId;
  final String kind;
  final DateTime capturedAtUtc;
  final double? latitude;
  final double? longitude;
  final double? accuracyM;
  final double? altitudeM;
  final double? speedMps;
  final double? headingDeg;
  final bool isMocked;
  final int? batteryPct;

  QueuedPing({
    required this.uuid,
    required this.attendanceLogId,
    required this.kind,
    required DateTime capturedAt,
    this.latitude,
    this.longitude,
    this.accuracyM,
    this.altitudeM,
    this.speedMps,
    this.headingDeg,
    this.isMocked = false,
    this.batteryPct,
  }) : capturedAtUtc = capturedAt.toUtc();

  bool get hasFix => latitude != null && longitude != null;

  /// The server's per-point contract (POST /api/me/tracking/pings). Absent
  /// optional values are omitted rather than sent as null.
  Map<String, dynamic> toJson() => {
        'client_uuid': uuid,
        'kind': kind,
        'captured_at': capturedAtUtc.toIso8601String(),
        'latitude': ?latitude,
        'longitude': ?longitude,
        'accuracy_m': ?_finite(accuracyM, min: 0),
        'altitude_m': ?_finite(altitudeM),
        'speed_mps': ?_finite(speedMps, min: 0),
        'heading_deg': ?_finite(headingDeg, min: 0, max: 360),
        'is_mocked': isMocked,
        'battery_pct': ?batteryPct,
      };

  // Android reports -1 / NaN for "unknown" speed, heading or accuracy; the server
  // would drop the whole point as invalid, so an unknown value is simply omitted.
  static double? _finite(double? v, {double? min, double? max}) {
    if (v == null || v.isNaN || v.isInfinite) return null;
    if (min != null && v < min) return null;
    if (max != null && v > max) return null;
    return v;
  }

  Map<String, Object?> toRow() => {
        'uuid': uuid,
        'attendance_log_id': attendanceLogId,
        'kind': kind,
        'captured_at': capturedAtUtc.toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        'accuracy_m': accuracyM,
        'altitude_m': altitudeM,
        'speed_mps': speedMps,
        'heading_deg': headingDeg,
        'is_mocked': isMocked ? 1 : 0,
        'battery_pct': batteryPct,
      };

  factory QueuedPing.fromRow(Map<String, Object?> r) => QueuedPing(
        uuid: r['uuid'] as String,
        attendanceLogId: _int(r['attendance_log_id']) ?? 0,
        kind: r['kind'] as String,
        capturedAt: DateTime.parse(r['captured_at'] as String),
        latitude: _num(r['latitude']),
        longitude: _num(r['longitude']),
        accuracyM: _num(r['accuracy_m']),
        altitudeM: _num(r['altitude_m']),
        speedMps: _num(r['speed_mps']),
        headingDeg: _num(r['heading_deg']),
        isMocked: _int(r['is_mocked']) == 1,
        batteryPct: _int(r['battery_pct']),
      );
}
