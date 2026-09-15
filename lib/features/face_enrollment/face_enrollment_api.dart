import '../../core/auth/session_controller.dart';
import '../../core/http/endpoints.dart';
import '../face/face_models.dart';

/// The server calls behind enrolling your face from this phone (server migration
/// 061). Abstract so the screen is tested against a scripted fake.
abstract class FaceEnrollmentApi {
  /// A liveness challenge. The server issues one only while HR's one-time pass is
  /// open (`FACE_ENROLLMENT_NO_PASS` otherwise).
  Future<FaceChallenge> challenge();

  /// Send the fingerprint and the photo of its frame for HR to review.
  /// `FACE_ENROLLMENT_BLOCKED` when the face already belongs to another employee.
  Future<void> submit(FaceCapture capture);
}

/// The real thing: mobile-only endpoints, through the session's guard so a revoked
/// switch or an expired token signs the phone out in one place.
class MobileFaceEnrollmentApi implements FaceEnrollmentApi {
  final SessionController session;

  const MobileFaceEnrollmentApi(this.session);

  @override
  Future<FaceChallenge> challenge() => session.guard(() => session.client.post(
        Endpoints.faceEnrollmentChallenge,
        parse: (d) => FaceChallenge.fromJson(d as Map<String, dynamic>),
      ));

  @override
  Future<void> submit(FaceCapture capture) =>
      session.guard(() => session.client.post(Endpoints.faceEnrollment, body: capture.toEnrollmentJson()));
}
