import 'package:hris_mobile/core/location/location_fix.dart';
import 'package:flutter/foundation.dart';
import 'package:hris_mobile/core/device/device_readiness_service.dart';
import 'package:hris_mobile/features/tracking/tracking_models.dart';
import 'package:hris_mobile/features/tracking/tracking_service.dart';
import 'package:hris_mobile/core/location/location_gate_service.dart';
import 'package:hris_mobile/features/face/face_capture_screen.dart';
import 'package:hris_mobile/features/face/face_models.dart';
import 'package:hris_mobile/features/time_clock/clock_api.dart';
import 'package:hris_mobile/features/time_clock/clock_models.dart';

Map<String, dynamic> statusJson({
  Map<String, dynamic>? today,
  bool consent = true,
  bool worksite = true,
  bool faceEnrolled = true,
  /// The MOBILE consent (migration 059) — the one that actually gates the app.
  /// Separate from [consent] so a test can drive the two apart and prove the
  /// web's flag does not unlock the phone.
  bool mobileConsent = true,
  /// The work-hours `tracking` block; omitted (= an older server) when null.
  Map<String, dynamic>? tracking,
  /// `face.self_enrollment` (server migration 061); omitted when null.
  Map<String, dynamic>? selfEnrollment,
}) => {
      'tracking': ?tracking,
      'server_time': '2026-09-11T00:12:33.000Z',
      'timezone': 'Asia/Manila',
      'local_date': '2026-09-11',
      'clock_date': '2026-09-11',
      'employee': {'id': 2316, 'employee_code': 'EMP01670', 'first_name': 'Sofia', 'last_name': 'Sandbox', 'work_arrangement': 'field'},
      'today': today,
      'worksite': worksite
          ? {'branch_id': 1, 'branch_name': 'Head Office', 'configured': true, 'lat': 14.5513714, 'lng': 121.0175541, 'radius_m': 200, 'radius_is_default': true, 'enforcement': 'flag'}
          : {'branch_id': 1, 'branch_name': 'Head Office', 'configured': false, 'lat': null, 'lng': null, 'radius_m': null, 'radius_is_default': false, 'enforcement': 'flag'},
      'consent': {'consent_given': consent, 'consent_at': null, 'consent_withdrawn_at': null},
      'mobile_consent': {'consent_given': mobileConsent, 'consent_at': null, 'consent_withdrawn_at': null},
      'face': {
        'required': true,
        'enrolled': faceEnrolled,
        'model_version': 'human-3',
        'liveness_challenges': ['blink', 'turn_head'],
        'self_enrollment': ?selfEnrollment,
      },
    };

/// A capture the fake API accepts — shaped like the real thing (64 finite
/// doubles, a 64-char nonce, the issued actions echoed) so the model's own
/// usability checks are exercised rather than bypassed.
FaceCapture fakeCapture({List<String>? completed}) => FaceCapture(
      nonce: 'a' * 64,
      embedding: List<double>.generate(128, (i) => (i + 1) / 128),
      dims: 128,
      modelVersion: 'human-3',
      completedChallenges: completed ?? const ['blink', 'turn_head'],
    );

/// The face check, scripted. [captureResult] is what the capture 'screen'
/// returns; [calls] records the directions it was asked for.
class FakeFaceCapturer {
  FaceResult result = FaceCaptured(fakeCapture());
  final calls = <String>[];

  Future<FaceResult> call(String direction) async {
    calls.add(direction);
    return result;
  }
}

Map<String, dynamic> clockedIn() => {
      'attendance_log_id': 1,
      'clock_in_at': '2026-09-11T00:13:00.000Z',
      'clock_out_at': null,
      'status': 'present',
      'clock_in_method': 'mobile',
      'clock_out_method': null,
    };

/// A scripted clock API: returns [status_], records punches, throws
/// [punchError] when set, and flips today to "clocked in" after a punch.
class FakeClockApi implements ClockApi {
  Map<String, dynamic> status_ = statusJson();
  Object? punchError;
  Object? challengeError;
  final punches = <Map<String, dynamic>>[];
  final challenges = <String>[];
  int consents = 0;
  int statusCalls = 0;

  @override
  Future<ClockStatus> status() async {
    statusCalls++;
    return ClockStatus.fromJson(status_);
  }

  @override
  Future<FaceChallenge> faceChallenge(String direction) async {
    challenges.add(direction);
    if (challengeError != null) throw challengeError!;
    return FaceChallenge(nonce: 'a' * 64, actions: const ['blink', 'turn_head']);
  }

  @override
  Future<PunchResponse> punch({
    required String direction,
    required LocationFix fix,
    required FaceCapture capture,
  }) async {
    // The whole submitted body, so a test can assert the face payload travelled
    // with the geotag rather than trusting that it did.
    punches.add({'direction': direction, ...fix.toJson(), ...capture.toJson()});
    if (punchError != null) throw punchError!;
    status_ = statusJson(today: clockedIn());
    return PunchResponse.fromJson({
      'direction': direction,
      'clock_in_at': '2026-09-11T00:13:00.000Z',
      'clock_out_at': null,
      'attendance_log_id': 1,
      'server_time': '2026-09-11T00:13:00.500Z',
      'match_distance': 0.31,
      'location': {
        'flagged': false,
        'flag_reason': null,
        'worksite': {'distance_m': 41, 'within': true, 'radius_m': 200},
      },
    });
  }

  @override
  Future<void> grantConsent() async {
    consents++;
    status_ = statusJson();
  }
}

class FakeFixService implements LocationFixService {
  LocationFix next = LocationFix(latitude: 14.5515, longitude: 121.0177, accuracyM: 9, isMocked: false, at: DateTime.now());
  bool timeout = false;
  int acquired = 0;

  @override
  Future<LocationFix> acquire() async {
    acquired++;
    if (timeout) throw const FixTimeout();
    return next;
  }
}

class AlwaysOkGate implements LocationGateService {
  @override
  Future<GateVerdict> check() async => GateVerdict.ok;
  @override
  Future<GateVerdict> requestForeground() async => GateVerdict.ok;
  @override
  Future<GateVerdict> requestBackground() async => GateVerdict.ok;
  @override
  Future<void> openAppSettings() async {}
  @override
  Future<void> openLocationSettings() async {}
}

/// Records what the controller asked the tracking service to do.
class FakeTrackingService implements TrackingService {
  final ValueNotifier<TrackingSnapshot> notifier = ValueNotifier(TrackingSnapshot.idle);
  final synced = <TrackingState>[];
  final stops = <String>[];

  @override
  ValueListenable<TrackingSnapshot> get snapshot => notifier;

  @override
  Future<void> sync(TrackingState state) async => synced.add(state);

  @override
  Future<void> stop({String reason = 'clocked_out'}) async => stops.add(reason);
}

Map<String, dynamic> trackingJson({bool active = true, int? attendanceLogId = 1}) => {
      'active': active,
      'attendance_log_id': attendanceLogId,
      'since': active ? '2026-09-11T00:13:00.000Z' : null,
      'policy': {'distance_filter_m': 25, 'min_interval_s': 30, 'heartbeat_s': 300, 'max_shift_hours': 16},
    };

/// Notifications granted, battery unrestricted: the setup wizard never shows.
class AlwaysReadyDevice implements DeviceReadinessService {
  @override
  Future<DeviceReadiness> check() async => DeviceReadiness.ready;
  @override
  Future<void> requestNotifications() async {}
  @override
  Future<void> requestBatteryExemption() async {}
  @override
  Future<void> openAppSettings() async {}
  @override
  Future<Set<String>> skippedSteps() async => const {};
  @override
  Future<void> skipStep(String name) async {}
}
