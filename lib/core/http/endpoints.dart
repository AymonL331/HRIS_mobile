/// Every server path the app uses, in one place. Paths are relative to the
/// environment's base URL and always start with `/api`.
abstract final class Endpoints {
  static const login = '/api/auth/login';
  static const me = '/api/auth/me';
  static const changePassword = '/api/auth/change-password';

  static const mobileClockStatus = '/api/me/mobile-clock/status';
  static const mobileClock = '/api/me/mobile-clock';

  /// The liveness challenge a punch must answer. Shared with the WEB field
  /// clock — a challenge is surface-agnostic (it issues a nonce and an ordered
  /// action sequence; what differs is which endpoint consumes it), so the app
  /// reuses the existing route rather than asking for a second one.
  static const faceChallenge = '/api/me/face-clock/challenge';
  /// The WEB field clock's consent. The app no longer writes this — kept only
  /// because the constant documents the pair below it.
  static const locationConsent = '/api/me/location-consent';

  /// The MOBILE APP's own RA 10173 consent (migration 059). A separate record
  /// from the one above because the app demands always-on PRECISE location,
  /// which is a wider collection than the punch-time geotag the web consent
  /// describes. Mobile-token only; a web session gets 403 MOBILE_ONLY.
  static const mobileLocationConsent = '/api/me/mobile-location-consent';

  /// WORK-HOURS LOCATION TRACKING (server migration 060): the batches of points
  /// the tracking service recorded between clock-in and clock-out, including the
  /// ones queued offline. Mobile-token only.
  static const trackingPings = '/api/me/tracking/pings';
  static const attendanceCalendar = '/api/me/attendance/calendar';

  /// My payslips. Ownership-scoped on the server (`resolveSelf` forces the
  /// employee from the signed-in account), so there is no employee id to pass
  /// and none to tamper with. Already inside the mobile token's `/api/me/`
  /// window, so the payslip module needed no server change at all.
  static const payslips = '/api/me/payslips';
  static String payslip(int id) => '/api/me/payslips/$id';
  static String payslipBreakdown(int id) => '/api/me/payslips/$id/breakdown';

  /// The ONE console route a mobile token may read: the team DTR, for a login
  /// that holds attendance:view. GET only; the server refuses everything else
  /// under /api/attendance with MOBILE_SCOPE.
  static const teamCalendar = '/api/attendance/calendar';
}
