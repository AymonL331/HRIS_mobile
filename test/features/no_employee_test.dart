import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/app.dart';
import 'package:hris_mobile/core/auth/session_controller.dart';
import 'package:hris_mobile/core/auth/session_store.dart';
import 'package:hris_mobile/core/config/env_store.dart';
import 'package:hris_mobile/core/location/location_fix.dart';
import 'package:hris_mobile/core/location/location_gate_service.dart';
import 'package:hris_mobile/features/attendance/team_api.dart';
import 'package:hris_mobile/features/time_clock/clock_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/clock_fakes.dart';
import '../fakes/team_fakes.dart';

void main() {
  testWidgets('a Super Admin (no employee) sees "No employee record" on the clock, EVERYONE on Attendance, and Settings still works', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final envStore = EnvStore();
    await envStore.load();
    final api = FakeClockApi();
    final team = FakeTeamApi({});
    final mock = MockClient((req) async => http.Response(
          jsonEncode({
            'success': true, 'message': 'OK', 'error': null,
            'data': {
              'token': 'T',
              'user': {'id': 1, 'tenant_id': 1, 'employee_id': null, 'username': 'admin', 'email': 'a@t.test', 'role_name': 'Super Admin', 'must_change_password': 0, 'mobile_access_enabled': 0, 'permissions': []},
              'tenant': {'id': 1, 'code': 'headoffice', 'name': 'Head Office'},
            },
          }),
          200,
        ));
    final session = SessionController(env: envStore, store: InMemorySessionStore(), appVersion: '1', httpClient: mock);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<EnvStore>.value(value: envStore),
        ChangeNotifierProvider<SessionController>.value(value: session),
        Provider<LocationGateService>.value(value: AlwaysOkGate()),
        Provider<LocationFixService>.value(value: FakeFixService()),
        Provider<ClockApi?>.value(value: api),
        Provider<TeamAttendanceApi?>.value(value: team),
      ],
      child: const HrisApp(),
    ));
    await session.login(companyCode: 'headoffice', identifier: 'admin', password: 'x');
    await tester.pumpAndSettle();

    // Navigation is the sidebar now, so each destination is a drawer trip.
    Future<void> go(String label) async {
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    expect(find.text('No employee record'), findsOneWidget);
    expect(api.statusCalls, 0); // nothing was asked of the clock API
    await go('Attendance');
    // A Super Admin holds every grant: the tab is the team DTR, not a dead end.
    expect(find.text('No employee record'), findsNothing);
    expect(find.text('Search name or employee code'), findsOneWidget);
    expect(find.text('No employees to show for this day.'), findsOneWidget);
    expect(team.calls.length, 1);
    expect(find.text('Mine'), findsNothing); // no own DTR to switch to

    // My Payslips is the same story: no employee, so no `/api/me/payslips` call
    // to 404 — the page says so instead.
    await go('My Payslips');
    expect(find.text('No employee record'), findsOneWidget);

    await go('Settings');
    expect(find.text('admin'), findsWidgets);
    // Settings explains where a password reset comes from; it does NOT offer a
    // self-service change. HR resets the login, the server issues a temporary
    // password, and the holder replaces it through the forced screen.
    expect(find.text('Password'), findsOneWidget);
    expect(find.textContaining('ask HR'), findsOneWidget);
    expect(find.text('Change password'), findsNothing);
  });
}
