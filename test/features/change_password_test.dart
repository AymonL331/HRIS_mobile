import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/app.dart';
import 'package:hris_mobile/core/auth/session_controller.dart';
import 'package:hris_mobile/core/auth/session_store.dart';
import 'package:hris_mobile/core/config/env_store.dart';
import 'package:hris_mobile/core/location/location_fix.dart';
import 'package:hris_mobile/core/location/location_gate_service.dart';
import 'package:hris_mobile/features/face/face_models.dart';
import 'package:hris_mobile/features/time_clock/clock_api.dart';
import 'package:hris_mobile/features/time_clock/clock_models.dart';
import 'package:hris_mobile/features/auth/change_password_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

String env({bool success = true, String message = 'OK', Object? data, Object? error}) =>
    jsonEncode({'success': success, 'message': message, 'data': data, 'error': error});

Map<String, dynamic> userJson({int mustChange = 1}) => {
      'id': 42, 'tenant_id': 1, 'employee_id': 7, 'username': 'olive', 'email': 'o@t.test',
      'role_name': 'Employee', 'must_change_password': mustChange, 'mobile_access_enabled': 1,
    };

void main() {
  group('local validation', () {
    test('mirrors the server rules', () {
      expect(_v('', 'Newpass123', 'Newpass123'), containsPair('current_password', contains('required')));
      expect(_v('old', 'short', 'short'), containsPair('new_password', contains('8–72')));
      expect(_v('Samepass1', 'Samepass1', 'Samepass1'), containsPair('new_password', contains('different')));
      expect(_v('old', 'Newpass123', 'Newpass124'), containsPair('confirm_password', contains('match')));
      expect(_v('old', 'Newpass123', 'Newpass123'), isEmpty);
    });
  });

  testWidgets('a forced account is shown the change screen; a wrong current password is a field error; success releases the shell', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final envStore = EnvStore();
    await envStore.load();
    var phase = 'login';
    final mock = MockClient((req) async {
      if (req.url.path == '/api/auth/login') {
        return http.Response(env(data: {'token': 'T', 'user': userJson(), 'tenant': {'id': 1, 'code': 'c', 'name': 'Co'}}), 200);
      }
      if (req.url.path == '/api/auth/change-password') {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body.keys, containsAll(['current_password', 'new_password']));
        if (phase == 'wrong') {
          return http.Response(env(success: false, message: 'Validation failed.', error: {'current_password': 'Incorrect current password.'}), 422);
        }
        return http.Response(env(message: 'Password changed.', data: null), 200);
      }
      return http.Response(env(success: false, message: 'nope', error: 'x'), 404);
    });
    final session = SessionController(env: envStore, store: InMemorySessionStore(), appVersion: '1', httpClient: mock);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<EnvStore>.value(value: envStore),
        ChangeNotifierProvider<SessionController>.value(value: session),
        Provider<LocationGateService>.value(value: _AlwaysOk()),
        Provider<LocationFixService>.value(value: _NoFix()),
        Provider<ClockApi?>.value(value: _StubClock()),
      ],
      child: const HrisApp(),
    ));
    await session.login(companyCode: 'c', identifier: 'u', password: 'Temp@1234');
    await tester.pumpAndSettle();

    expect(find.byType(ChangePasswordScreen), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget); // the forced escape hatch
    expect(find.text('Time Clock'), findsNothing);

    // Local rule first: nothing sent.
    await tester.tap(find.text('Save new password'));
    await tester.pumpAndSettle();
    expect(find.text('Your current password is required.'), findsOneWidget);

    phase = 'wrong';
    await tester.enterText(find.widgetWithText(TextField, 'Current password'), 'guess');
    await tester.enterText(find.widgetWithText(TextField, 'New password'), 'Sandbox@123');
    await tester.enterText(find.widgetWithText(TextField, 'Confirm new password'), 'Sandbox@123');
    await tester.tap(find.text('Save new password'));
    await tester.pumpAndSettle();
    expect(find.text('Incorrect current password.'), findsOneWidget);
    expect(session.state, isA<MustChangePassword>());

    phase = 'ok';
    await tester.enterText(find.widgetWithText(TextField, 'Current password'), 'Temp@1234');
    await tester.tap(find.text('Save new password'));
    // The shell's Time Clock ticks every second, so it never "settles"; pump a
    // few frames instead.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(session.state, isA<SignedIn>());
    expect(find.byType(ChangePasswordScreen), findsNothing);
    expect(find.text('Time Clock'), findsWidgets);
  });
}

Map<String, String> _v(String c, String n, String k) => validateChangePassword(current: c, next: n, confirm: k);

class _NoFix implements LocationFixService {
  @override
  Future<LocationFix> acquire() async => throw const FixTimeout();
}

class _StubClock implements ClockApi {
  @override
  Future<ClockStatus> status() async => ClockStatus.fromJson({
        'server_time': '2026-09-11T00:00:00.000Z', 'timezone': 'Asia/Manila', 'local_date': '2026-09-11', 'clock_date': '2026-09-11',
        'employee': {'first_name': 'Olive', 'last_name': 'Office', 'employee_code': 'E1'}, 'today': null,
        'worksite': {'configured': false}, 'consent': {'consent_given': true},
        'face': {'required': true, 'enrolled': true, 'model_version': 'human-3', 'liveness_challenges': ['blink']},
      });
  @override
  Future<FaceChallenge> faceChallenge(String direction) => throw UnimplementedError();
  @override
  Future<PunchResponse> punch({
    required String direction,
    required LocationFix fix,
    required FaceCapture capture,
  }) =>
      throw UnimplementedError();
  @override
  Future<void> grantConsent() async {}
}

class _AlwaysOk implements LocationGateService {
  @override
  Future<GateVerdict> check() async => GateVerdict.ok;
  @override
  Future<void> openAppSettings() async {}
  @override
  Future<void> openLocationSettings() async {}
}
