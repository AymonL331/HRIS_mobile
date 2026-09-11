import '../../core/auth/session_controller.dart';
import '../../core/http/endpoints.dart';
import '../../core/location/location_fix.dart';
import 'clock_models.dart';

/// The three server calls the Time Clock makes. Abstract so the controller and
/// the screen are tested against a scripted fake.
abstract class ClockApi {
  Future<ClockStatus> status();
  Future<PunchResponse> punch({required String direction, required LocationFix fix});
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
  Future<PunchResponse> punch({required String direction, required LocationFix fix}) => session.guard(() => session.client.post(
        Endpoints.mobileClock,
        body: {'direction': direction, 'location': fix.toJson()},
        parse: (d) => PunchResponse.fromJson(d as Map<String, dynamic>),
      ));

  @override
  Future<void> grantConsent() => session.guard(() => session.client.post(Endpoints.locationConsent));
}
