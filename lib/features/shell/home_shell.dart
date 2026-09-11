import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/session_controller.dart';
import '../../core/location/location_fix.dart';
import '../attendance/attendance_api.dart';
import '../attendance/attendance_controller.dart';
import '../attendance/attendance_screen.dart';
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

  static const _titles = ['Time Clock', 'My Attendance', 'Settings'];

  @override
  Widget build(BuildContext context) {
    // A login with no employee (a Super Admin, a special account) has nothing to
    // clock and no DTR; both tabs say so instead of firing calls that 404.
    final hasEmployee = context.watch<SessionController>().user?.employeeId != null;
    final pages = <Widget>[
      hasEmployee ? const TimeClockScreen() : const NoEmployeeScreen(what: 'time clock'),
      hasEmployee ? const AttendanceScreen() : const NoEmployeeScreen(what: 'attendance record'),
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
      ],
      child: Scaffold(
        appBar: AppBar(title: Text(_titles[_index])),
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

