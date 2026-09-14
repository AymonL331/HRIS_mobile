import '../../core/auth/session_controller.dart';
import '../../core/http/endpoints.dart';
import '../../core/location/location_fix.dart';
import '../face/face_models.dart';
import 'clock_models.dart';

/// The server calls the Time Clock makes. Abstract so the controller and the
/// screen are tested against a scripted fake.
abstract class ClockApi {
  Future<ClockStatus> status();

  /// Ask for the liveness challenge a punch must answer. Issued BEFORE the
  /// on-device liveness runs, so the server's randomized sequence is what the
  /// employee has to perform and a pre-recorded attempt cannot have known it.
  Future<FaceChallenge> faceChallenge(String direction);

  /// Record a punch. Since 2026-09-13 the mobile clock is face-gated: [capture]
  /// carries the nonce, the embedding and the actions actually performed, and
  /// the server verifies all three before anything is written.
  Future<PunchResponse> punch({
    required String direction,
    required LocationFix fix,
    required FaceCapture capture,
  });

  Future<void> grantConsent();
}

/// The real thing: the mobile-only endpoints, through the session's guard so a
/// revoked switch or an expired token signs the phone out in one place.
class MobileClockApi implements ClockApi {
  final SessionController session;

  const MobileClockApi(this.session);

  @override
  Future<ClockStatus> status() => session.guard(() => session.client.get(
        Endpoints.mobileClockStatus,
        parse: (d) => ClockStatus.fromJson(d as Map<String, dynamic>),
      ));

  @override
  Future<FaceChallenge> faceChallenge(String direction) => session.guard(() => session.client.post(
        Endpoints.faceChallenge,
        body: {'direction': direction},
        parse: (d) => FaceChallenge.fromJson(d as Map<String, dynamic>),
      ));

  @override
  Future<PunchResponse> punch({
    required String direction,
    required LocationFix fix,
    required FaceCapture capture,
  }) =>
      session.guard(() => session.client.post(
            Endpoints.mobileClock,
            // The face payload and the geotag travel together: the server
            // refuses a punch missing either, so there is no request shape here
            // that could record a punch without both.
            body: {'direction': direction, 'location': fix.toJson(), ...capture.toJson()},
            parse: (d) => PunchResponse.fromJson(d as Map<String, dynamic>),
          ));

  // The APP's own consent, not the web field clock's — see Endpoints.
  @override
  Future<void> grantConsent() => session.guard(() => session.client.post(Endpoints.mobileLocationConsent));
}
