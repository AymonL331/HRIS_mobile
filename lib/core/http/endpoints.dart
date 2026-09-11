/// Every server path the app uses, in one place. Paths are relative to the
/// environment's base URL and always start with `/api`.
abstract final class Endpoints {
  static const login = '/api/auth/login';
  static const me = '/api/auth/me';
  static const changePassword = '/api/auth/change-password';

  static const mobileClockStatus = '/api/me/mobile-clock/status';
  static const mobileClock = '/api/me/mobile-clock';
  static const locationConsent = '/api/me/location-consent';
  static const attendanceCalendar = '/api/me/attendance/calendar';

  /// The ONE console route a mobile token may read: the team DTR, for a login
  /// that holds attendance:view. GET only; the server refuses everything else
  /// under /api/attendance with MOBILE_SCOPE.
  static const teamCalendar = '/api/attendance/calendar';
}
