import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/session_controller.dart';
import '../../core/device/device_readiness_service.dart';
import '../../core/device/phone_state_service.dart';
import '../../core/location/location_fix.dart';
import '../../core/location/location_gate_service.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/brand_mark.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/user_avatar.dart';
import '../attendance/attendance_api.dart';
import '../attendance/attendance_controller.dart';
import '../attendance/attendance_screen.dart';
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
import '../tracking/phone_setup.dart';
import '../tracking/tracking_gaps.dart';
import '../tracking/tracking_service.dart';
import '../travel_orders/travel_order_api.dart';
import '../travel_orders/travel_orders_screen.dart';
import '../accountabilities/accountabilities_api.dart';
import '../accountabilities/accountabilities_screen.dart';
import '../home/home_api.dart';
import '../home/home_screen.dart';
import '../leave/leave_api.dart';
import '../leave/leave_screen.dart';
import '../leave_calendar/leave_calendar_api.dart';
import '../leave_calendar/leave_calendar_screen.dart';
import '../my_profile/my_profile_api.dart';
import '../my_profile/my_profile_screen.dart';
import '../overtime/overtime_api.dart';
import '../overtime/overtime_screen.dart';
import '../payslips/payslip_detail_screen.dart';
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

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  ReminderTapRelay? _taps;

  /// Sends the phone's settings to HR (server migration 125): now, on every
  /// return to the screen, and at each clock-in. Null without an employee or in
  /// a test without the location/settings services.
  PhoneSettingsReporter? _phoneReporter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final session = context.read<SessionController>();
    final gate = _optional<LocationGateService>(context);
    final device = _optional<DeviceReadinessService>(context);
    if (session.user?.employeeId != null && gate != null && device != null) {
      _phoneReporter = PhoneSettingsReporter(
        api: _optional<PhoneSettingsApi?>(context) ?? MobilePhoneSettingsApi(session),
        gate: gate,
        device: device,
        phone: _optional<PhoneStateService>(context),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) => _phoneReporter?.report());
    }
    // A tapped reminder notification opens the Time Clock (user decision
    // 2026-09-17) — whether the tap launched the app (the relay already holds
    // it) or landed while any page was showing.
    _taps = _optional<ReminderTapRelay>(context);
    _taps?.addListener(_onReminderTap);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onReminderTap());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _taps?.removeListener(_onReminderTap);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the settings page the employee was just sent to, or a setting
    // changed while away: the newest state goes to HR.
    if (state == AppLifecycleState.resumed) _phoneReporter?.report();
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
    // firing `/api/me/*` calls that 404. Attendance is ONLY my own record: the
    // team view (everyone's DTR for attendance:view holders) was removed on
    // 2026-10-27 — no phone shows other people's attendance (the server refuses
    // it too, 403 MOBILE_TEAM_ATTENDANCE_OFF).
    final user = context.watch<SessionController>().user;
    final hasEmployee = user?.employeeId != null;
    const attendanceTitle = 'My Attendance';
    final titles = [
      'My Time Clock', attendanceTitle, 'My Payslips', 'Profile Photo', 'Settings', 'My Travel Orders',
      // The rest of the website's Self-Service (2026-11-23): new indexes so the
      // older destinations keep their numbers.
      'Home', 'My Profile', 'My Accountabilities', 'My Leave', 'Overtime & Holiday Work', 'Leave Calendar',
    ];
    final session = context.read<SessionController>();
    void go(int i) => setState(() => _index = i);
    // Home's links, by the website's sidebar keys (constants/nav.js).
    const byKey = {
      'time-clock': 0, 'attendance': 1, 'payslips': 2, 'profile-photo': 3, 'travel-orders': 5,
      'home': 6, 'profile': 7, 'accountabilities': 8, 'leave': 9, 'overtime': 10, 'leave-calendar': 11,
    };
    void navigate(String key) {
      final i = byKey[key];
      if (i != null) go(i);
    }
    final Widget attendance = hasEmployee ? const AttendanceScreen() : const NoEmployeeScreen(what: 'attendance record');
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
      // MY TRAVEL ORDERS (2026-10-29): the web page on the phone — file, check in,
      // proof, remarks. Index 5 so the older destinations keep their numbers.
      hasEmployee
          ? TravelOrdersScreen(
              api: _optional<TravelOrderApi?>(context) ?? MobileTravelOrderApi(session),
              fixes: context.read<LocationFixService>(),
              baseUrl: session.env.baseUrl,
              onOpenTimeClock: () => setState(() => _index = 0),
              onOpenProfilePhoto: () => setState(() => _index = 3),
              active: _index == 5,
            )
          : const NoEmployeeScreen(what: 'travel order'),
      // 6 HOME — the website's /employee page.
      hasEmployee
          ? HomeScreen(
              api: _optional<HomeApi?>(context) ?? MobileHomeApi(session),
              username: user?.username ?? '',
              onNavigate: navigate,
              onOpenPayslip: (id) => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => PayslipDetailScreen(
                  payslipId: id,
                  api: _optional<PayslipApi?>(context) ?? MobilePayslipApi(session),
                ),
              )),
              active: _index == 6,
            )
          : const NoEmployeeScreen(what: 'home page'),
      // 7 MY PROFILE
      hasEmployee
          ? MyProfileScreen(
              api: _optional<MyProfileApi?>(context) ?? MobileMyProfileApi(session),
              baseUrl: session.env.baseUrl,
              canSendPhoto: user?.canSendProfilePhoto ?? false,
              photoApi: _profilePhotoApiOf(context) ?? MobileProfilePhotoApi(session),
              onPhotoChanged: session.setProfilePhotoUrl,
              active: _index == 7,
            )
          : const NoEmployeeScreen(what: 'profile'),
      // 8 MY ACCOUNTABILITIES
      hasEmployee
          ? AccountabilitiesScreen(
              api: _optional<AccountabilitiesApi?>(context) ?? MobileAccountabilitiesApi(session),
              active: _index == 8,
            )
          : const NoEmployeeScreen(what: 'accountability record'),
      // 9 MY LEAVE
      hasEmployee
          ? MyLeaveScreen(api: _optional<LeaveApi?>(context) ?? MobileLeaveApi(session), active: _index == 9)
          : const NoEmployeeScreen(what: 'leave record'),
      // 10 OVERTIME & HOLIDAY WORK
      hasEmployee
          ? OvertimeScreen(
              api: _optional<OvertimeApi?>(context) ?? MobileOvertimeApi(session),
              baseUrl: session.env.baseUrl,
              onNavigate: navigate,
              active: _index == 10,
            )
          : const NoEmployeeScreen(what: 'overtime record'),
      // 11 LEAVE CALENDAR
      hasEmployee
          ? LeaveCalendarScreen(
              api: _optional<LeaveCalendarApi?>(context) ?? MobileLeaveCalendarApi(session),
              active: _index == 11,
            )
          : const NoEmployeeScreen(what: 'leave calendar'),
    ];
    final sections = [
      // The website's Self-Service, in its order (constants/nav.js). My Time Clock
      // (named as on the website) sits after My Attendance, before My Travel
      // Orders (user 2026-11-24).
      NavSection('Self-Service', [
        const NavDestination(index: 6, label: 'Home', icon: Icons.home_outlined, selectedIcon: Icons.home),
        const NavDestination(index: 7, label: 'My Profile', icon: Icons.badge_outlined, selectedIcon: Icons.badge),
        const NavDestination(
          index: 2,
          label: 'My Payslips',
          icon: Icons.receipt_long_outlined,
          selectedIcon: Icons.receipt_long,
        ),
        const NavDestination(
          index: 8,
          label: 'My Accountabilities',
          icon: Icons.inventory_2_outlined,
          selectedIcon: Icons.inventory_2,
        ),
        const NavDestination(index: 9, label: 'My Leave', icon: Icons.event_available_outlined, selectedIcon: Icons.event_available),
        const NavDestination(
          index: 10,
          label: 'Overtime & Holiday Work',
          icon: Icons.more_time_outlined,
          selectedIcon: Icons.more_time,
        ),
        NavDestination(
          index: 1,
          label: attendanceTitle,
          icon: Icons.calendar_month_outlined,
          selectedIcon: Icons.calendar_month,
        ),
        const NavDestination(
          index: 0,
          label: 'My Time Clock',
          icon: Icons.punch_clock_outlined,
          selectedIcon: Icons.punch_clock,
        ),
        const NavDestination(
          index: 5,
          label: 'My Travel Orders',
          icon: Icons.location_on_outlined,
          selectedIcon: Icons.location_on,
        ),
        const NavDestination(index: 11, label: 'Leave Calendar', icon: Icons.date_range_outlined, selectedIcon: Icons.date_range),
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
          create: (ctx) {
            final tracking = _trackingOf(ctx);
            final gate = _optional<LocationGateService>(ctx);
            final device = _optional<DeviceReadinessService>(ctx);
            final phone = _optional<PhoneStateService>(ctx);
            return TimeClockController(
              api: ctx.read<ClockApi?>() ?? MobileClockApi(ctx.read<SessionController>()),
              fixes: ctx.read<LocationFixService>(),
              tracking: tracking,
              reminders: _optional<ReminderSync?>(ctx),
              // Steps 2 + 5 of the tracking fix (2026-11-13): settings re-checked
              // at every clock-in; long gaps explained before clock-out.
              clockInCheck: gate == null || device == null
                  ? null
                  : () async {
                      final problem = await trackingReadinessProblem(gate: gate, device: device, phone: phone);
                      // What the phone looked like at this clock-in, for HR —
                      // sent whether or not the clock-in goes through.
                      unawaited(_phoneReporter?.report(force: true));
                      return problem;
                    },
              beforeClockOut: tracking == null
                  ? null
                  : (id) => explainGapsBeforeClockOut(
                        ctx,
                        attendanceLogId: id,
                        api: _optional<TrackingGapsApi?>(ctx) ?? MobileTrackingGapsApi(ctx.read<SessionController>()),
                        tracking: tracking,
                      ),
            );
          },
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
            // Home draws its own "Welcome, …" header, as the website does.
            if (!(_index == 6 && hasEmployee)) PageHeader(titles[_index]),
            Expanded(
              // Hidden pages keep their state but stop animating (a page not yet
              // opened shows its loading spinner): no ticking off-screen.
              child: IndexedStack(
                index: _index,
                children: [
                  for (var i = 0; i < pages.length; i++) TickerMode(enabled: i == _index, child: pages[i]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
