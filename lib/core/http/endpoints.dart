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
}
