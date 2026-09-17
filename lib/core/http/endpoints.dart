/// Every server path the app uses, in one place. Paths are relative to the
/// environment's base URL and always start with `/api`.
abstract final class Endpoints {
  static const login = '/api/auth/login';
  static const me = '/api/auth/me';
  static const changePassword = '/api/auth/change-password';

  /// IN-APP UPDATE (2026-09-15): the newest published APK and the oldest build still
  /// allowed. PUBLIC — no token — so the check also runs on the login screen. The
  /// download path comes back in the response.
  static const appUpdateLatest = '/api/mobile-app/latest';

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

  /// FACE SELF-ENROLLMENT (server migration 061): where I stand (HR's one-time
  /// pass / waiting for review / refused), a liveness challenge issued only while
  /// the pass is open, and the submission (fingerprint + one JPEG). Mobile-token only.
  static const faceEnrollment = '/api/me/face-enrollment';
  static const faceEnrollmentChallenge = '/api/me/face-enrollment/challenge';
  static const attendanceCalendar = '/api/me/attendance/calendar';

  /// My payslips. Ownership-scoped on the server (`resolveSelf` forces the
  /// employee from the signed-in account), so there is no employee id to pass
  /// and none to tamper with. Already inside the mobile token's `/api/me/`
  /// window, so the payslip module needed no server change at all.
  static const payslips = '/api/me/payslips';
  static String payslip(int id) => '/api/me/payslips/$id';
  static String payslipBreakdown(int id) => '/api/me/payslips/$id/breakdown';

  /// PROFILE PHOTO (server migration 062): my current photo and where the last one I
  /// sent stands (GET), and a new camera photo for HR to approve (POST — needs the
  /// `profile_photo:create` grant). Mobile-token only.
  static const profilePhoto = '/api/me/profile-photo';

  /// CLOCK-IN / CLOCK-OUT REMINDERS (2026-09-17). The bell reads the same rows the
  /// website's bell does, narrowed to the reminder ladder (`kinds=reminders`); the
  /// schedule is the ladder as alarm instants, mobile-token only — the phone arms
  /// an alarm per stage and, when it fires, asks `/notifications` what was sent.
  static const notifications = '/api/me/notifications';
  static const notificationsUnreadCount = '/api/me/notifications/unread-count';
  static const notificationsReadAll = '/api/me/notifications/read-all';
  static String notification(int id) => '/api/me/notifications/$id';
  static String notificationRead(int id) => '/api/me/notifications/$id/read';
  static String notificationAcknowledge(int id) => '/api/me/notifications/$id/acknowledge';
  static const reminderSchedule = '/api/me/reminder-schedule';

  /// The ONE console route a mobile token may read: the team DTR, for a login
  /// that holds attendance:view. GET only; the server refuses everything else
  /// under /api/attendance with MOBILE_SCOPE.
  static const teamCalendar = '/api/attendance/calendar';
}
