import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/session_controller.dart';
import '../../core/location/location_fix.dart';
import '../attendance/attendance_api.dart';
import '../attendance/attendance_controller.dart';
import '../attendance/attendance_screen.dart';
import '../attendance/attendance_tab.dart';
import '../attendance/team_api.dart';
import '../attendance/team_controller.dart';
import '../attendance/team_screen.dart';
import '../auth/change_password_screen.dart';
import '../settings/settings_screen.dart';
import '../time_clock/clock_api.dart';
import '../time_clock/time_clock_controller.dart';
import '../time_clock/time_clock_screen.dart';
import 'no_employee_screen.dart';

/// The signed-in shell: three tabs. The Time Clock controller lives here so
/// switching tabs keeps its state (the last outcome, the last fix).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    // A login with no employee (a Super Admin, a special account) has nothing to
    // clock; the tab says so instead of firing calls that 404. The Attendance
    // tab depends on TWO things: an employee record (my own DTR) and the
    // attendance:view grant (everyone's DTR, read-only) — any combination.
    final user = context.watch<SessionController>().user;
    final hasEmployee = user?.employeeId != null;
    final canTeam = user?.canViewTeamAttendance ?? false;
    final titles = ['Time Clock', canTeam ? 'Attendance' : 'My Attendance', 'Settings'];
    final Widget attendance = hasEmployee && canTeam
        ? const AttendanceTab()
        : canTeam
            ? const TeamAttendanceScreen()
            : hasEmployee
                ? const AttendanceScreen()
                : const NoEmployeeScreen(what: 'attendance record');
    final pages = <Widget>[
      hasEmployee ? const TimeClockScreen() : const NoEmployeeScreen(what: 'time clock'),
      attendance,
      SettingsScreen(
        onChangePassword: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ChangePasswordScreen(forced: false)),
        ),
      ),
    ];
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<TimeClockController>(
          create: (ctx) => TimeClockController(
            api: ctx.read<ClockApi?>() ?? MobileClockApi(ctx.read<SessionController>()),
            fixes: ctx.read<LocationFixService>(),
          ),
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
      ],
      child: Scaffold(
        appBar: AppBar(title: Text(titles[_index])),
        body: IndexedStack(index: _index, children: pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.punch_clock_outlined), selectedIcon: Icon(Icons.punch_clock), label: 'Time Clock'),
            NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Attendance'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
          ],
        ),
      ),
    );
  }
}

