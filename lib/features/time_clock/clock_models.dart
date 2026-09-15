import '../../core/location/geo.dart';
import '../../core/time/manila_time.dart';
import '../face_enrollment/face_enrollment_models.dart';
import '../tracking/tracking_models.dart';

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

/// The face gate, as the server describes it (`face` block).
///
/// [required] is sent as a constant `true` by the server, deliberately: the app
/// must never read "not enrolled" as "then I may punch without a face". When
/// [enrolled] is false the employee cannot clock at all until HR enrols them,
/// and the home screen says so instead of letting them reach a camera that will
/// be refused.
class FaceGate {
  final bool required;
  final bool enrolled;
  final String modelVersion;
  final List<String> livenessChallenges;

  /// Enrolling from this phone (server migration 061): HR's one-time pass, a
  /// submission waiting for review, or the last refusal.
  final SelfEnrollmentState selfEnrollment;

  const FaceGate({
    required this.required,
    required this.enrolled,
    required this.modelVersion,
    required this.livenessChallenges,
    this.selfEnrollment = SelfEnrollmentState.none,
  });

  factory FaceGate.fromJson(Map<String, dynamic>? j) => j == null
      // A server that predates the face gate. Treated as "not required" so an
      // older deployment keeps working rather than bricking every punch.
      ? const FaceGate(required: false, enrolled: false, modelVersion: '', livenessChallenges: [])
      : FaceGate(
          required: _flag(j['required']),
          enrolled: _flag(j['enrolled']),
          modelVersion: (j['model_version'] ?? '') as String,
          livenessChallenges:
              ((j['liveness_challenges'] as List?) ?? const []).map((e) => '$e').toList(growable: false),
          selfEnrollment: SelfEnrollmentState.fromJson(j['self_enrollment'] as Map<String, dynamic>?),
        );

  /// May this employee punch right now, as far as the face gate is concerned?
  bool get canPunch => !required || enrolled;
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
  final FaceGate face;

  /// Whether the phone should be recording the work-hours trail right now.
  final TrackingState tracking;

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
    required this.face,
    this.tracking = TrackingState.inactive,
  });

  bool get canClockIn => today == null || today!.clockInAt == null;
  bool get canClockOut => today?.clockInAt != null && today?.clockOutAt == null;

  factory ClockStatus.fromJson(Map<String, dynamic> j) {
    final emp = (j['employee'] as Map<String, dynamic>?) ?? const {};
    // The MOBILE consent (migration 059) is what gates this app. The `consent`
    // block is the WEB field clock's and is echoed read-only. Falling back to it
    // keeps a build pointed at a pre-059 server working rather than locking
    // everyone out of an app whose consent endpoint does not exist yet.
    final consent = (j['mobile_consent'] as Map<String, dynamic>?) ??
        (j['consent'] as Map<String, dynamic>?) ??
        const {};
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
      face: FaceGate.fromJson(j['face'] as Map<String, dynamic>?),
      tracking: TrackingState.fromJson(j['tracking'] as Map<String, dynamic>?),
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

  /// How close the submitted face was to the enrolled template, as the SERVER
  /// measured it. Present on a face-verified punch; kept so the success card can
  /// say the punch was face-verified rather than merely claiming it.
  final double? matchDistance;

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
    required this.matchDistance,
  });

  bool get faceVerified => matchDistance != null;

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
      matchDistance: _num(j['match_distance']),
    );
  }
}
