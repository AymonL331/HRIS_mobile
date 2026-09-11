import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/app.dart';
import 'package:hris_mobile/core/auth/session_controller.dart';
import 'package:hris_mobile/core/auth/session_store.dart';
import 'package:hris_mobile/core/config/env_store.dart';
import 'package:hris_mobile/core/location/location_fix.dart';
import 'package:hris_mobile/core/location/location_gate_service.dart';
import 'package:hris_mobile/features/auth/env_settings_sheet.dart';
import 'package:hris_mobile/features/time_clock/clock_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/clock_fakes.dart';

String env({bool success = true, String message = 'OK', Object? data, Object? error}) =>
    jsonEncode({'success': success, 'message': message, 'data': data, 'error': error});

Map<String, dynamic> userJson() => {
      'id': 42, 'tenant_id': 1, 'employee_id': 7, 'username': 'olive', 'email': 'o@t.test',
      'role_name': 'Employee', 'must_change_password': 0, 'mobile_access_enabled': 1,
    };

/// Boots the app to the login screen with a scripted server.
Future<({SessionController session, EnvStore env, List<http.Request> seen})> boot(
  WidgetTester tester,
  Future<http.Response> Function(http.Request req) handler,
) async {
  SharedPreferences.setMockInitialValues({});
  final envStore = EnvStore();
  await envStore.load();
  final seen = <http.Request>[];
  final mock = MockClient((req) {
    seen.add(req);
    return handler(req);
  });
  final session = SessionController(env: envStore, store: InMemorySessionStore(), appVersion: '1', httpClient: mock);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<EnvStore>.value(value: envStore),
      ChangeNotifierProvider<SessionController>.value(value: session),
      Provider<LocationGateService>.value(value: AlwaysOkGate()),
      Provider<LocationFixService>.value(value: FakeFixService()),
      Provider<ClockApi?>.value(value: FakeClockApi()),
    ],
    child: const HrisApp(),
  ));
  await session.bootstrap();
  await tester.pumpAndSettle();
  return (session: session, env: envStore, seen: seen);
}

Future<void> fillAndSubmit(WidgetTester tester, {String code = 'HEAD-OFFICE', String user = 'sofia', String pw = 'Sandbox@123'}) async {
  await tester.enterText(find.widgetWithText(TextField, 'Company or branch code'), code);
  await tester.enterText(find.widgetWithText(TextField, 'Username or email'), user);
  await tester.enterText(find.widgetWithText(TextField, 'Password'), pw);
  await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a 422 lands on the fields', (tester) async {
    await boot(tester, (_) async => http.Response(
          env(success: false, message: 'Validation failed.', error: {'company_code': 'Company code is required.', 'password': 'Password is required.'}),
          422,
        ));
    await fillAndSubmit(tester, code: '', pw: '');
    expect(find.text('Company code is required.'), findsOneWidget);
    expect(find.text('Password is required.'), findsOneWidget);
  });

  testWidgets('MOBILE_ACCESS_DISABLED shows the "ask HR" banner and sends client=mobile', (tester) async {
    final b = await boot(tester, (_) async => http.Response(
          env(success: false, message: 'Mobile app access is not enabled for this account. Ask HR to enable it.', error: {'code': 'MOBILE_ACCESS_DISABLED'}),
          403,
        ));
    await fillAndSubmit(tester);
    expect(find.textContaining("isn't enabled for the mobile app yet"), findsOneWidget);
    expect(jsonDecode(b.seen.single.body)['client'], 'mobile');
    expect(b.session.state, isA<SignedOut>());
  });

  testWidgets('a bad credential shows the server message unchanged', (tester) async {
    await boot(tester, (_) async => http.Response(
          env(success: false, message: 'Invalid company code, username/email, or password.', error: 'Invalid company code, username/email, or password.'),
          401,
        ));
    await fillAndSubmit(tester, pw: 'wrong');
    expect(find.text('Invalid company code, username/email, or password.'), findsOneWidget);
  });

  testWidgets('a wrong server address points at Advanced', (tester) async {
    await boot(tester, (_) async => http.Response('<html>ngrok</html>', 200));
    await fillAndSubmit(tester);
    expect(find.textContaining('Check the server address under Advanced'), findsOneWidget);
  });

  testWidgets('switching to Sandbox changes the address the next login goes to', (tester) async {
    final b = await boot(tester, (_) async => http.Response(env(data: {'token': 'T', 'user': userJson()}), 200));
    expect(find.text('http://192.168.137.1:5000'), findsOneWidget);
    await tester.tap(find.text('Sandbox'));
    await tester.pumpAndSettle();
    expect(find.text('https://turbine-chamomile-financial.ngrok-free.dev'), findsOneWidget);
    await fillAndSubmit(tester);
    expect(b.seen.first.url.path, '/api/auth/login');
    expect(b.seen.first.url.origin, 'https://turbine-chamomile-financial.ngrok-free.dev');
    expect(b.session.isSignedIn, isTrue);
    await tester.pumpWidget(const SizedBox()); // dispose the ticking shell
  });

  testWidgets('the Advanced sheet validates and saves the addresses', (tester) async {
    final b = await boot(tester, (_) async => http.Response(env(), 200));
    await tester.tap(find.text('Advanced…'));
    await tester.pumpAndSettle();
    expect(find.byType(EnvSettingsSheet), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Main HRIS'), 'not a url');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('starting with http://'), findsOneWidget);
    expect(b.env.config.mainUrl, 'http://192.168.137.1:5000');

    await tester.enterText(find.widgetWithText(TextField, 'Main HRIS'), 'https://hris.example.com/');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(EnvSettingsSheet), findsNothing);
    expect(b.env.config.mainUrl, 'https://hris.example.com');
    expect(find.text('https://hris.example.com'), findsOneWidget);
  });
}
