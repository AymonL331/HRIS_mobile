import '../../core/location/geo.dart';
import '../../core/time/manila_time.dart';

int? _int(Object? v) => v == null ? null : (v is int ? v : int.tryParse('$v'));
double? _num(Object? v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
bool _flag(Object? v) => v == true || v == 1 || v == '1';

/// The branch worksite the geofence is judged against (`worksite` block).
class Worksite {
  final int? branchId;
  final String? branchName;
  final bool configured;
  final double? lat;
  final double? lng;
  final int? radiusM;
  final String enforcement; // off | flag | block

  const Worksite({
    required this.branchId,
    required this.branchName,
    required this.configured,
    required this.lat,
    required this.lng,
    required this.radiusM,
    required this.enforcement,
  });

  factory Worksite.fromJson(Map<String, dynamic>? j) => j == null
      ? const Worksite(branchId: null, branchName: null, configured: false, lat: null, lng: null, radiusM: null, enforcement: 'flag')
      : Worksite(
          branchId: _int(j['branch_id']),
          branchName: j['branch_name'] as String?,
          configured: j['configured'] == true,
          lat: _num(j['lat']),
          lng: _num(j['lng']),
          radiusM: _int(j['radius_m']),
          enforcement: (j['enforcement'] ?? 'flag') as String,
        );

  /// Same answer the server gives: null when there is nothing to measure.
  ({int? distanceM, bool? within}) measure(double lat, double lng) {
    if (!configured || this.lat == null || this.lng == null || radiusM == null) {
      return (distanceM: null, within: null);
    }
    final d = haversineMeters(lat, lng, this.lat!, this.lng!).round();
    return (distanceM: d, within: d <= radiusM!);
  }
}

class TodayPunches {
  final int attendanceLogId;
  final DateTime? clockInAt;
  final DateTime? clockOutAt;
  final String? status;
  final String? clockInMethod;
  final String? clockOutMethod;

  const TodayPunches({
    required this.attendanceLogId,
    required this.clockInAt,
    required this.clockOutAt,
    required this.status,
    required this.clockInMethod,
    required this.clockOutMethod,
  });

  factory TodayPunches.fromJson(Map<String, dynamic> j) => TodayPunches(
        attendanceLogId: _int(j['attendance_log_id']) ?? 0,
        clockInAt: ManilaTime.parseUtc(j['clock_in_at'] as String?),
        clockOutAt: ManilaTime.parseUtc(j['clock_out_at'] as String?),
        status: j['status'] as String?,
        clockInMethod: j['clock_in_method'] as String?,
        clockOutMethod: j['clock_out_method'] as String?,
      );
}

/// `GET /api/me/mobile-clock/status`.
class ClockStatus {
  final DateTime serverTime;
  final String timezone;
  final String localDate;
  final String clockDate;
  final String employeeName;
  final String employeeCode;
  final TodayPunches? today;
  final Worksite worksite;
  final bool consentGiven;

  const ClockStatus({
    required this.serverTime,
    required this.timezone,
    required this.localDate,
    required this.clockDate,
    required this.employeeName,
    required this.employeeCode,
    required this.today,
    required this.worksite,
    required this.consentGiven,
  });

  bool get canClockIn => today == null || today!.clockInAt == null;
  bool get canClockOut => today?.clockInAt != null && today?.clockOutAt == null;

  factory ClockStatus.fromJson(Map<String, dynamic> j) {
    final emp = (j['employee'] as Map<String, dynamic>?) ?? const {};
    final consent = (j['consent'] as Map<String, dynamic>?) ?? const {};
    final today = j['today'];
    return ClockStatus(
      serverTime: ManilaTime.parseUtc(j['server_time'] as String?) ?? DateTime.now().toUtc(),
      timezone: (j['timezone'] ?? 'Asia/Manila') as String,
      localDate: (j['local_date'] ?? '') as String,
      clockDate: (j['clock_date'] ?? '') as String,
      employeeName: [emp['first_name'], emp['last_name']].whereType<String>().where((s) => s.isNotEmpty).join(' '),
      employeeCode: (emp['employee_code'] ?? '') as String,
      today: today is Map<String, dynamic> ? TodayPunches.fromJson(today) : null,
      worksite: Worksite.fromJson(j['worksite'] as Map<String, dynamic>?),
      consentGiven: _flag(consent['consent_given']),
    );
  }
}

/// `POST /api/me/mobile-clock` → the recorded punch.
class PunchResponse {
  final String direction;
  final DateTime? clockInAt;
  final DateTime? clockOutAt;
  final DateTime? serverTime;
  final bool flagged;
  final String? flagReason;
  final int? distanceM;
  final bool? within;
  final int? radiusM;

  const PunchResponse({
    required this.direction,
    required this.clockInAt,
    required this.clockOutAt,
    required this.serverTime,
    required this.flagged,
    required this.flagReason,
    required this.distanceM,
    required this.within,
    required this.radiusM,
  });

  DateTime? get stampedAt => direction == 'in' ? clockInAt : clockOutAt;

  factory PunchResponse.fromJson(Map<String, dynamic> j) {
    final loc = j['location'] as Map<String, dynamic>?;
    final ws = loc?['worksite'] as Map<String, dynamic>?;
    return PunchResponse(
      direction: (j['direction'] ?? '') as String,
      clockInAt: ManilaTime.parseUtc(j['clock_in_at'] as String?),
      clockOutAt: ManilaTime.parseUtc(j['clock_out_at'] as String?),
      serverTime: ManilaTime.parseUtc(j['server_time'] as String?),
      flagged: loc?['flagged'] == true,
      flagReason: loc?['flag_reason'] as String?,
      distanceM: _int(ws?['distance_m']),
      within: ws?['within'] is bool ? ws!['within'] as bool : null,
      radiusM: _int(ws?['radius_m']),
    );
  }
}
