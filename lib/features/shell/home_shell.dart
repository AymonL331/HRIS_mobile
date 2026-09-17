import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/session_controller.dart';
import '../../core/location/location_fix.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/brand_mark.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/user_avatar.dart';
import '../attendance/attendance_api.dart';
import '../attendance/attendance_controller.dart';
import '../attendance/attendance_screen.dart';
import '../attendance/attendance_tab.dart';
import '../attendance/team_api.dart';
import '../attendance/team_controller.dart';
import '../attendance/team_screen.dart';
import '../payslips/payslip_api.dart';
import '../payslips/payslips_controller.dart';
import '../payslips/payslips_screen.dart';
import '../profile_photo/profile_photo_api.dart';
import '../profile_photo/profile_photo_screen.dart';
import '../reminders/notification_bell.dart';
import '../reminders/notifications_controller.dart';
import '../reminders/notifications_screen.dart';
import '../reminders/reminder_coordinator.dart';
import '../reminders/reminder_notifier.dart';
import '../reminders/reminder_tap_relay.dart';
import '../reminders/reminders_api.dart';
import '../settings/settings_screen.dart';
import '../time_clock/clock_api.dart';
import '../time_clock/time_clock_controller.dart';
import '../time_clock/time_clock_screen.dart';
import '../tracking/tracking_service.dart';
import 'app_drawer.dart';
import 'no_employee_screen.dart';

/// A provided value, or null where none is provided. The widget tests that
/// mount the whole shell are about navigation: they provide no tracking
/// service (a real foreground service cannot run under a test), no reminder
/// machinery, and only the APIs they script — so every optional dependency is
/// read this way and the shell builds the real one, or nothing, in its place.
T? _optional<T>(BuildContext ctx) {
  try {
    return ctx.read<T>();
  } on ProviderNotFoundException {
    return null;
  }
}

TrackingService? _trackingOf(BuildContext ctx) => _optional<TrackingService>(ctx);

/// A profile-photo API injected by a test, or null (the shell then builds the real one
/// from the session).
ProfilePhotoApi? _profilePhotoApiOf(BuildContext ctx) => _optional<ProfilePhotoApi?>(ctx);

/// The signed-in shell. Navigation is the web SIDEBAR (a drawer behind the top
/// bar's menu button), not a tab bar: with My Payslips the app carries four
/// destinations and will carry more, which is past what three bottom tabs can
/// hold — and the sidebar is the shape this product already has in the browser.
///
/// The feature controllers live here so switching destinations keeps their
/// state (the clock's last outcome and last fix, the months already paged in,
/// the payslips already loaded). Sign out is the drawer's pinned footer.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  ReminderTapRelay? _taps;

  @override
  void initState() {
    super.initState();
    // A tapped reminder notification opens the Time Clock (user decision
    // 2026-09-17) — whether the tap launched the app (the relay already holds
    // it) or landed while any page was showing.
    _taps = _optional<ReminderTapRelay>(context);
    _taps?.addListener(_onReminderTap);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onReminderTap());
  }

  @override
  void dispose() {
    _taps?.removeListener(_onReminderTap);
    super.dispose();
  }

  void _onReminderTap() {
    final relay = _taps;
    if (relay == null || relay.value != reminderTapTimeClock || !mounted) return;
    relay.consume();
    Navigator.of(context).popUntil((r) => r.isFirst);
    setState(() => _index = 0);
  }

  @override
  Widget build(BuildContext context) {
    // A login with no employee (a Super Admin, a special account) has nothing to
    // clock, no DTR of its own and no payslips; those pages say so instead of
    // firing `/api/me/*` calls that 404. The Attendance page depends on TWO
    // things: an employee record (my own DTR) and the attendance:view grant
    // (everyone's DTR, read-only) — any combination.
    final user = context.watch<SessionController>().user;
    final hasEmployee = user?.employeeId != null;
    final canTeam = user?.canViewTeamAttendance ?? false;
    final attendanceTitle = canTeam ? 'Attendance' : 'My Attendance';
    final titles = ['Time Clock', attendanceTitle, 'My Payslips', 'Profile Photo', 'Settings'];
    final session = context.read<SessionController>();
    final Widget attendance = hasEmployee && canTeam
        ? const AttendanceTab()
        : canTeam
        ? const TeamAttendanceScreen()
        : hasEmployee
        ? const AttendanceScreen()
        : const NoEmployeeScreen(what: 'attendance record');
    final pages = <Widget>[
      hasEmployee
          // No profile photo yet → the card points at Profile Photo (index 3).
          ? TimeClockScreen(onOpenProfilePhoto: () => setState(() => _index = 3))
          : const NoEmployeeScreen(what: 'time clock'),
      attendance,
      hasEmployee ? const PayslipsScreen() : const NoEmployeeScreen(what: 'payslip'),
      // Server migration 062: a new photo waits for HR before it replaces this one.
      hasEmployee
          ? ProfilePhotoScreen(
              api: _profilePhotoApiOf(context) ?? MobileProfilePhotoApi(session),
              baseUrl: session.env.baseUrl,
              canSend: user?.canSendProfilePhoto ?? false,
              // An approval lands while the app is open: the avatars follow it here.
              onPhotoChanged: session.setProfilePhotoUrl,
            )
          : const NoEmployeeScreen(what: 'profile photo'),
      const SettingsScreen(),
    ];
    final sections = [
      NavSection('Self-Service', [
        const NavDestination(
          index: 0,
          label: 'Time Clock',
          icon: Icons.punch_clock_outlined,
          selectedIcon: Icons.punch_clock,
        ),
        NavDestination(
          index: 1,
          label: attendanceTitle,
          icon: Icons.calendar_month_outlined,
          selectedIcon: Icons.calendar_month,
        ),
        const NavDestination(
          index: 2,
          label: 'My Payslips',
          icon: Icons.receipt_long_outlined,
          selectedIcon: Icons.receipt_long,
        ),
      ]),
      const NavSection('Account', [
        NavDestination(
          index: 3,
          label: 'Profile Photo',
          icon: Icons.account_circle_outlined,
          selectedIcon: Icons.account_circle,
        ),
        NavDestination(index: 4, label: 'Settings', icon: Icons.settings_outlined, selectedIcon: Icons.settings),
      ]),
    ];

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<TimeClockController>(
          create: (ctx) => TimeClockController(
            api: ctx.read<ClockApi?>() ?? MobileClockApi(ctx.read<SessionController>()),
            fixes: ctx.read<LocationFixService>(),
            tracking: _trackingOf(ctx),
            reminders: _optional<ReminderSync?>(ctx),
          ),
        ),
        // The bell. Not lazy: the badge and the 30 s poll must run from the
        // moment the shell is up, not from the first time the bell is drawn.
        // A login with no employee never starts it (nothing to fetch).
        ChangeNotifierProvider<NotificationsController>(
          lazy: false,
          create: (ctx) {
            final c = NotificationsController(
              api: _optional<NotificationsApi?>(ctx) ?? MobileNotificationsApi(ctx.read<SessionController>()),
              notifier: _optional<ReminderNotifier?>(ctx),
            );
            if (hasEmployee) c.start();
            return c;
          },
        ),
        ChangeNotifierProvider<AttendanceController>(
          create: (ctx) => AttendanceController(
            api: ctx.read<AttendanceApi?>() ?? MobileAttendanceApi(ctx.read<SessionController>()),
          ),
        ),
        // Lazy (provider default): created only when the team view first reads it.
        ChangeNotifierProvider<TeamAttendanceController>(
          create: (ctx) => TeamAttendanceController(
            api: ctx.read<TeamAttendanceApi?>() ?? MobileTeamAttendanceApi(ctx.read<SessionController>()),
          ),
        ),
        ChangeNotifierProvider<PayslipsController>(
          create: (ctx) =>
              PayslipsController(api: ctx.read<PayslipApi?>() ?? MobilePayslipApi(ctx.read<SessionController>())),
        ),
      ],
      // The web shell: the brand top bar with the menu button and the account
      // avatar, a page header on the page background, then the content. The
      // destinations live in the drawer.
      child: Scaffold(
        appBar: AppBar(
          title: const BrandMark(),
          actions: [
            if (hasEmployee)
              Builder(
                builder: (ctx) => NotificationBell(
                  onOpen: () => NotificationsScreen.open(ctx, ctx.read<NotificationsController>()),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(right: HrisSpace.s5),
              child: UserAvatar(
                user?.username ?? '',
                imageUrl: user?.profileImageUrl,
                baseUrl: session.env.baseUrl,
              ),
            ),
          ],
        ),
        drawer: AppDrawer(
          sections: sections,
          selectedIndex: _index,
          onSelect: (i) => setState(() => _index = i),
          username: user?.username ?? '',
          roleName: user?.roleName,
          photoUrl: user?.profileImageUrl,
          baseUrl: session.env.baseUrl,
          // The drawer closes first; the confirmation then opens over the page.
          onSignOut: () => confirmSignOut(context),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(titles[_index]),
            Expanded(
              child: IndexedStack(index: _index, children: pages),
            ),
          ],
        ),
      ),
    );
  }
}
