import '../../core/auth/session_controller.dart';

/// My Profile — the web's GET /api/me/profile and /api/me/profile-sections,
/// both self-scoped on the server (req.me.employeeId). Inside the mobile
/// token's `/api/me/` window.
abstract class MyProfileApi {
  /// The employees.getDetail shape: the employee row + org names, compensation,
  /// reporting_to, account, biometric.
  Future<Map<String, dynamic>> profile();

  /// { work_history, education, family_members, background_disclosures, references }.
  Future<Map<String, dynamic>> sections();
}

class MobileMyProfileApi implements MyProfileApi {
  static const profilePath = '/api/me/profile';
  static const sectionsPath = '/api/me/profile-sections';

  final SessionController session;

  const MobileMyProfileApi(this.session);

  @override
  Future<Map<String, dynamic>> profile() => session.guard(() => session.client.get(
        profilePath,
        parse: (d) => (d as Map<String, dynamic>?) ?? const {},
      ));

  @override
  Future<Map<String, dynamic>> sections() => session.guard(() => session.client.get(
        sectionsPath,
        parse: (d) => (d as Map<String, dynamic>?) ?? const {},
      ));
}
