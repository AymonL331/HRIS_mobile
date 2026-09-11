import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/auth/session_controller.dart';
import 'package:hris_mobile/core/auth/session_store.dart';
import 'package:hris_mobile/core/config/app_env.dart';
import 'package:hris_mobile/core/config/env_store.dart';
import 'package:hris_mobile/core/http/api_exception.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

String env({bool success = true, String message = 'OK', Object? data, Object? error}) =>
    jsonEncode({'success': success, 'message': message, 'data': data, 'error': error});

Map<String, dynamic> userJson({int mustChange = 0, int mobile = 1}) => {
      'id': 42,
      'tenant_id': 1,
      'employee_id': 7,
      'username': 'olive',
      'email': 'olive@t.test',
      'role_name': 'Employee',
      'must_change_password': mustChange,
      'mobile_access_enabled': mobile,
    };

Future<SessionController> make(MockClient mock, {InMemorySessionStore? store, AppEnv selected = AppEnv.main}) async {
  SharedPreferences.setMockInitialValues({'env.selected': selected.name});
  final envStore = EnvStore();
  await envStore.load();
  return SessionController(env: envStore, store: store ?? InMemorySessionStore(), appVersion: '1.0.0', httpClient: mock);
}

void main() {
  test('bootstrap with no stored session -> SignedOut, no request made', () async {
    var calls = 0;
    final s = await make(MockClient((_) async {
      calls++;
      return http.Response(env(), 200);
    }));
    await s.bootstrap();
    expect(s.state, isA<SignedOut>());
    expect(calls, 0);
  });

  test('login posts client=mobile, stores the token per env, routes to SignedIn', () async {
    late http.Request seen;
    final store = InMemorySessionStore();
    final s = await make(
      MockClient((req) async {
        seen = req;
        return http.Response(
          env(data: {'token': 'T1', 'user': userJson(), 'tenant': {'id': 1, 'code': 'headoffice', 'name': 'Head Office'}}),
          200,
        );
      }),
      store: store,
    );
    await s.login(companyCode: 'headoffice', identifier: 'olive', password: 'pw');
    expect(jsonDecode(seen.body)['client'], 'mobile');
    expect(s.state, isA<SignedIn>());
    expect(s.user!.username, 'olive');
    expect(s.tenant!.name, 'Head Office');
    expect((await store.read('main'))!.token, 'T1');
    expect(await store.read('sandbox'), isNull);
  });

  test('login for a forced-password account routes to MustChangePassword; markPasswordChanged releases it', () async {
    final s = await make(MockClient((_) async => http.Response(env(data: {'token': 'T', 'user': userJson(mustChange: 1)}), 200)));
    await s.login(companyCode: 'c', identifier: 'u', password: 'p');
    expect(s.state, isA<MustChangePassword>());
    s.markPasswordChanged();
    expect(s.state, isA<SignedIn>());
    expect(s.user!.mustChangePassword, isFalse);
  });

  test('login refused MOBILE_ACCESS_DISABLED propagates and stores nothing', () async {
    final store = InMemorySessionStore();
    final s = await make(
      MockClient((_) async => http.Response(
            env(success: false, message: 'Mobile app access is not enabled for this account.', error: {'code': 'MOBILE_ACCESS_DISABLED'}),
            403,
          )),
      store: store,
    );
    await s.bootstrap();
    await expectLater(
      s.login(companyCode: 'c', identifier: 'u', password: 'p'),
      throwsA(isA<ApiException>().having((e) => e.mobileAccessDisabled, 'mobileAccessDisabled', true)),
    );
    expect(s.state, isA<SignedOut>());
    expect(await store.read('main'), isNull);
  });

  test('bootstrap with a stored token validates via /auth/me and sends the bearer', () async {
    final store = InMemorySessionStore();
    await store.write('main', const SessionRecord(token: 'STORED'));
    late http.Request seen;
    final s = await make(
      MockClient((req) async {
        seen = req;
        return http.Response(env(data: userJson()), 200);
      }),
      store: store,
    );
    await s.bootstrap();
    expect(seen.url.path, '/api/auth/me');
    expect(seen.headers['Authorization'], 'Bearer STORED');
    expect(s.state, isA<SignedIn>());
  });

  test('bootstrap sees the switch turned off on /auth/me and signs out with the reason', () async {
    final store = InMemorySessionStore();
    await store.write('main', const SessionRecord(token: 'STORED'));
    final s = await make(MockClient((_) async => http.Response(env(data: userJson(mobile: 0)), 200)), store: store);
    await s.bootstrap();
    expect(s.state, isA<SignedOut>().having((x) => x.reason, 'reason', contains('disabled')));
    expect(await store.read('main'), isNull);
  });

  test('bootstrap with a rejected token forgets it and explains', () async {
    final store = InMemorySessionStore();
    await store.write('main', const SessionRecord(token: 'STALE'));
    final s = await make(
      MockClient((_) async => http.Response(env(success: false, message: 'Invalid or expired token.', error: 'x'), 401)),
      store: store,
    );
    await s.bootstrap();
    expect(s.state, isA<SignedOut>().having((x) => x.reason, 'reason', contains('expired')));
    expect(await store.read('main'), isNull);
  });

  test('bootstrap with the server unreachable keeps the token and explains', () async {
    final store = InMemorySessionStore();
    await store.write('main', const SessionRecord(token: 'KEEP'));
    final s = await make(MockClient((_) async => throw http.ClientException('refused')), store: store);
    await s.bootstrap();
    expect(s.state, isA<SignedOut>().having((x) => x.reason, 'reason', contains('Cannot reach')));
    expect((await store.read('main'))!.token, 'KEEP');
  });

  test('guard: MOBILE_ACCESS_DISABLED mid-session signs out with the reason; PASSWORD_CHANGE_REQUIRED routes', () async {
    var phase = 'login';
    final s = await make(MockClient((_) async {
      switch (phase) {
        case 'login':
          return http.Response(env(data: {'token': 'T', 'user': userJson()}), 200);
        case 'disabled':
          return http.Response(env(success: false, message: 'Mobile app access has been disabled for this account.', error: {'code': 'MOBILE_ACCESS_DISABLED'}), 403);
        default:
          return http.Response(env(success: false, message: 'Change it.', error: {'code': 'PASSWORD_CHANGE_REQUIRED'}), 403);
      }
    }));
    await s.login(companyCode: 'c', identifier: 'u', password: 'p');
    phase = 'pw';
    await expectLater(s.guard(() => s.client.get('/api/me/profile')), throwsA(isA<ApiException>()));
    expect(s.state, isA<MustChangePassword>());
    phase = 'disabled';
    await expectLater(s.guard(() => s.client.get('/api/me/profile')), throwsA(isA<ApiException>()));
    expect(s.state, isA<SignedOut>().having((x) => x.reason, 'reason', contains('disabled')));
  });

  test('switchEnv drops the session and changes the base URL the client uses', () async {
    final store = InMemorySessionStore();
    final urls = <String>[];
    final s = await make(
      MockClient((req) async {
        urls.add(req.url.origin);
        return http.Response(env(data: {'token': 'T', 'user': userJson()}), 200);
      }),
      store: store,
    );
    await s.login(companyCode: 'c', identifier: 'u', password: 'p');
    expect(s.isSignedIn, isTrue);
    await s.switchEnv(AppEnv.sandbox);
    expect(s.state, isA<SignedOut>());
    expect(await store.read('main'), isNull);
    await s.login(companyCode: 'c', identifier: 'u', password: 'p');
    expect(urls.last, 'https://turbine-chamomile-financial.ngrok-free.dev');
    expect((await store.read('sandbox'))!.token, 'T');
  });
}
