import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/auth/user.dart';
import 'package:hris_mobile/core/http/api_exception.dart';
import 'package:hris_mobile/features/attendance/team_controller.dart';
import 'package:hris_mobile/features/attendance/team_models.dart';
import 'package:hris_mobile/features/attendance/team_screen.dart';
import 'package:provider/provider.dart';

import '../fakes/team_fakes.dart';

// 2026-09-11 02:00 UTC = 10:00 AM Manila, so "today" is 2026-09-11.
DateTime nowUtc() => DateTime.utc(2026, 9, 11, 2);

Map<String, dynamic> roster() => pageJson([
      cell(1, 'Ana Alonzo', code: 'EMP001', inAt: '2026-09-10T23:55:00.000Z', outAt: '2026-09-11T09:00:00.000Z'),
      cell(2, 'Ben Bautista', code: 'EMP002', status: 'late', inAt: '2026-09-11T01:30:00.000Z', extra: {
        'is_late': true, 'late_minutes': 90, 'capture_method': 'mobile', 'clock_in_method': 'mobile',
        'location_in_address': 'Arnaiz Avenue, Makati',
        'worksite': {'branch_id': 1, 'in_distance_m': 1740, 'in_within': false, 'out_distance_m': null, 'out_within': null},
      }),
      cell(3, 'Cara Cruz', code: 'EMP003', dayType: 'absent', status: 'absent'),
      cell(4, 'Dan Dizon', code: 'EMP004', dayType: 'no_record', status: null),
    ]);

Future<TeamAttendanceController> mount(WidgetTester tester, FakeTeamApi api) async {
  final c = TeamAttendanceController(api: api, nowUtc: nowUtc);
  await tester.pumpWidget(ChangeNotifierProvider<TeamAttendanceController>.value(
    value: c,
    child: const MaterialApp(home: Scaffold(body: TeamAttendanceScreen())),
  ));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  group('User grants', () {
    test('attendance:view or the Super Admin role opens the team view; a plain employee has neither', () {
      final hr = User.fromJson({'id': 1, 'tenant_id': 1, 'employee_id': 5, 'username': 'hr', 'email': '', 'role_name': 'HR', 'permissions': ['attendance:view', 'employees:update']});
      final admin = User.fromJson({'id': 2, 'tenant_id': 1, 'employee_id': null, 'username': 'admin', 'email': '', 'role_name': 'Super Admin', 'permissions': []});
      final emp = User.fromJson({'id': 3, 'tenant_id': 1, 'employee_id': 9, 'username': 'e', 'email': '', 'role_name': 'Employee'});
      expect(hr.canViewTeamAttendance, isTrue);
      expect(admin.canViewTeamAttendance, isTrue);
      expect(emp.canViewTeamAttendance, isFalse);
      expect(emp.permissions, isEmpty);
      expect(hr.copyWith(mustChangePassword: true).permissions, hr.permissions);
    });
  });

  group('TeamDay', () {
    test('parses the verdicts and place labels, holds no coordinate', () {
      final d = TeamDay.fromJson((roster()['items'] as List)[1] as Map<String, dynamic>);
      expect(d.employeeName, 'Ben Bautista');
      expect(d.employeeCode, 'EMP002');
      expect(d.status, 'late');
      expect(d.lateMinutes, 90);
      expect(d.isMobilePunch, isTrue);
      expect(d.inWithin, isFalse);
      expect(d.outWithin, isNull);
      expect(d.outOfRange, isTrue);
      expect(d.inAddress, 'Arnaiz Avenue, Makati');
      expect(d.clockInAt, DateTime.utc(2026, 9, 11, 1, 30));
      expect(d.toString().contains('14.55'), isFalse);
    });

    test('a nameless cell (employee since removed) falls back to the id', () {
      final d = TeamDay.fromJson(cell(77, '', dayType: 'no_record', status: null));
      expect(d.employeeName, 'Employee #77');
    });

    test('a page reads its pagination block', () {
      final p = TeamDayPage.fromJson('2026-09-11', pageJson([cell(1, 'A')], page: 1, totalPages: 3, total: 250));
      expect(p.hasMore, isTrue);
      expect(p.total, 250);
      expect(TeamDayPage.fromJson('2026-09-11', {'items': []}).hasMore, isFalse);
    });
  });

  group('TeamAttendanceController', () {
    test('starts on the Manila today, steps back and forward but never past today', () async {
      final api = FakeTeamApi({'2026-09-11': roster(), '2026-09-10': pageJson([cell(1, 'Ana Alonzo', date: '2026-09-10')])});
      final c = TeamAttendanceController(api: api, nowUtc: nowUtc);
      expect(c.date, '2026-09-11');
      expect(c.isToday, isTrue);
      await c.load();
      expect(c.items.length, 4);
      expect(c.presentCount, 1);
      expect(c.lateCount, 1);
      expect(c.count('absent'), 1);
      expect(c.count('no_record'), 1);
      expect(c.outOfRangeCount, 1);

      await c.previousDay();
      expect(c.date, '2026-09-10');
      expect(c.items.single.employeeName, 'Ana Alonzo');
      await c.nextDay();
      expect(c.date, '2026-09-11');
      await c.nextDay(); // no future
      expect(c.date, '2026-09-11');
      await c.setDate('2027-01-01'); // clamped
      expect(c.date, '2026-09-11');
      expect(api.calls, ['2026-09-11||1', '2026-09-10||1', '2026-09-11||1']);
    });

    test('search is debounced and sent to the API', () async {
      final api = FakeTeamApi({'2026-09-11': roster()});
      final c = TeamAttendanceController(api: api, nowUtc: nowUtc);
      await c.load();
      c.setSearch('b');
      c.setSearch('be');
      c.setSearch('ben');
      expect(api.calls.length, 1); // nothing yet
      await Future<void>.delayed(TeamAttendanceController.searchDebounce + const Duration(milliseconds: 50));
      expect(api.calls, ['2026-09-11||1', '2026-09-11|ben|1']);
      expect(c.items.single.employeeName, 'Ben Bautista');
      c.dispose();
    });

    test('loadMore appends the next page; a failure keeps what was loaded', () async {
      final api = FakeTeamApi(
        {'2026-09-11': pageJson([cell(1, 'A'), cell(2, 'B')], page: 1, totalPages: 2, total: 3)},
        pages: {('2026-09-11', 2): pageJson([cell(3, 'C')], page: 2, totalPages: 2, total: 3)},
      );
      final c = TeamAttendanceController(api: api, nowUtc: nowUtc);
      await c.load();
      expect(c.hasMore, isTrue);
      await c.loadMore();
      expect(c.items.map((i) => i.employeeName), ['A', 'B', 'C']);
      expect(c.hasMore, isFalse);

      api.error = const ApiException(status: 500, code: 'X', message: 'Server hiccup');
      await c.refresh();
      expect(c.error, 'Server hiccup');
      expect(c.items.length, 3, reason: 'a failed refresh does not blank the list');
    });
  });

  group('TeamAttendanceScreen', () {
    testWidgets('lists everyone for today with badges, chips and the summary line', (tester) async {
      final api = FakeTeamApi({'2026-09-11': roster()});
      await mount(tester, api);
      expect(find.text('Friday, 11 September 2026'), findsOneWidget);
      expect(find.text('Ana Alonzo'), findsOneWidget);
      expect(find.text('Ben Bautista'), findsOneWidget);
      expect(find.text('Present'), findsOneWidget);
      expect(find.text('Late'), findsOneWidget);
      expect(find.text('Absent'), findsOneWidget);
      expect(find.text('No record'), findsOneWidget);
      expect(find.text('Late 90 min'), findsOneWidget);
      expect(find.text('Mobile app'), findsOneWidget);
      expect(find.text('Out of range'), findsOneWidget);
      expect(find.textContaining('In: Arnaiz Avenue, Makati'), findsOneWidget);
      expect(find.text('7:55 AM  →  5:00 PM'), findsOneWidget);
      expect(find.text('4 employees · 1 present · 1 late · 1 absent · 1 no record · 1 out of range'), findsOneWidget);
      // Today: no forward step, no "Today" shortcut.
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right)).onPressed, isNull);
      expect(find.text('Today'), findsNothing);
    });

    testWidgets('stepping back loads that day and offers the way back to today', (tester) async {
      final api = FakeTeamApi({'2026-09-11': roster(), '2026-09-10': pageJson([cell(1, 'Ana Alonzo', date: '2026-09-10', dayType: 'rest_day', status: null)])});
      await mount(tester, api);
      await tester.tap(find.byTooltip('Previous day'));
      await tester.pumpAndSettle();
      expect(find.text('Thursday, 10 September 2026'), findsOneWidget);
      expect(find.text('Rest day'), findsOneWidget);
      expect(find.text('Ben Bautista'), findsNothing);
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      expect(find.text('Friday, 11 September 2026'), findsOneWidget);
      expect(find.text('Ben Bautista'), findsOneWidget);
    });

    testWidgets('typing in the search filters after the debounce; clearing restores', (tester) async {
      final api = FakeTeamApi({'2026-09-11': roster()});
      await mount(tester, api);
      await tester.enterText(find.byType(TextField), 'cruz');
      await tester.pump(TeamAttendanceController.searchDebounce + const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(find.text('Cara Cruz'), findsOneWidget);
      expect(find.text('Ana Alonzo'), findsNothing);
      await tester.tap(find.byTooltip('Clear'));
      await tester.pump(TeamAttendanceController.searchDebounce + const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(find.text('Ana Alonzo'), findsOneWidget);
    });

    testWidgets('a failed first load shows the error and Try again', (tester) async {
      final api = FakeTeamApi({})..error = const ApiException(status: 503, code: 'DOWN', message: 'Server unavailable');
      await mount(tester, api);
      expect(find.text('Server unavailable'), findsOneWidget);
      api.error = null;
      api.byDate['2026-09-11'] = roster();
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Ana Alonzo'), findsOneWidget);
    });
  });
}
