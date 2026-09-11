import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/http/api_client.dart';
import 'package:hris_mobile/core/http/api_exception.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ApiClient clientWith(MockClient mock, {String? token, void Function(String?)? onUnauthorized}) => ApiClient(
      baseUrl: 'http://api.test',
      tokenProvider: () async => token,
      appVersion: '1.2.3',
      platform: 'android',
      onUnauthorized: onUnauthorized,
      client: mock,
    );

String envelope({bool success = true, String message = 'OK', Object? data, Object? error}) =>
    jsonEncode({'success': success, 'message': message, 'data': data, 'error': error});

void main() {
  test('sends the bearer token, the ngrok bypass, the user agent and the app version', () async {
    late http.Request seen;
    final mock = MockClient((req) async {
      seen = req;
      return http.Response(envelope(data: {'ok': true}), 200);
    });
    final data = await clientWith(mock, token: 'tok').get<Map<String, dynamic>>('/api/auth/me');
    expect(data, {'ok': true});
    expect(seen.headers['Authorization'], 'Bearer tok');
    expect(seen.headers['ngrok-skip-browser-warning'], 'true');
    expect(seen.headers['User-Agent'], 'HRISMobile/1.2.3 (android)');
    expect(seen.headers['X-App-Version'], '1.2.3');
    expect(seen.url.toString(), 'http://api.test/api/auth/me');
  });

  test('no token means no Authorization header; POST sends JSON', () async {
    late http.Request seen;
    final mock = MockClient((req) async {
      seen = req;
      return http.Response(envelope(data: {'token': 't'}), 200);
    });
    await clientWith(mock).post('/api/auth/login', body: {'client': 'mobile'});
    expect(seen.headers.containsKey('Authorization'), isFalse);
    expect(seen.headers['Content-Type'], startsWith('application/json'));
    expect(jsonDecode(seen.body), {'client': 'mobile'});
  });

  test('query parameters are appended', () async {
    late http.Request seen;
    final mock = MockClient((req) async {
      seen = req;
      return http.Response(envelope(data: []), 200);
    });
    await clientWith(mock).get('/api/me/attendance/calendar', query: {'date_from': '2026-09-01', 'limit': '31'});
    expect(seen.url.queryParameters, {'date_from': '2026-09-01', 'limit': '31'});
  });

  test('parse is applied to data', () async {
    final mock = MockClient((_) async => http.Response(envelope(data: {'n': 7}), 200));
    final n = await clientWith(mock).get<int>('/x', parse: (d) => (d as Map)['n'] as int);
    expect(n, 7);
  });

  test('a 4xx envelope becomes an ApiException with its code', () async {
    final mock = MockClient((_) async => http.Response(
          envelope(success: false, message: 'Disabled.', error: {'code': 'MOBILE_ACCESS_DISABLED'}),
          403,
        ));
    await expectLater(
      clientWith(mock, token: 't').get('/api/me/profile'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'MOBILE_ACCESS_DISABLED')),
    );
  });

  test('a 401 calls onUnauthorized once, then throws', () async {
    final mock = MockClient((_) async => http.Response(
          envelope(success: false, message: 'Invalid or expired token.', error: 'Invalid or expired token.'),
          401,
        ));
    final seen = <String?>[];
    await expectLater(
      clientWith(mock, token: 'stale', onUnauthorized: seen.add).get('/api/auth/me'),
      throwsA(isA<ApiException>().having((e) => e.isUnauthorized, 'isUnauthorized', true)),
    );
    expect(seen, ['Invalid or expired token.']);
  });

  test('a non-JSON body (ngrok interstitial, wrong URL) is INVALID_ENVELOPE', () async {
    final mock = MockClient((_) async => http.Response('<html>ngrok</html>', 200));
    await expectLater(
      clientWith(mock).get('/api/auth/me'),
      throwsA(isA<ApiException>()
          .having((e) => e.code, 'code', 'INVALID_ENVELOPE')
          .having((e) => e.message, 'message', contains('api.test'))),
    );
  });

  test('a network failure is NETWORK_ERROR with status 0', () async {
    final mock = MockClient((_) async => throw http.ClientException('refused'));
    await expectLater(
      clientWith(mock).get('/api/auth/me'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'NETWORK_ERROR').having((e) => e.status, 'status', 0)),
    );
  });

  test('a slow server is TIMEOUT', () async {
    final mock = MockClient((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      return http.Response(envelope(), 200);
    });
    final client = ApiClient(
      baseUrl: 'http://api.test',
      tokenProvider: () async => null,
      appVersion: '1',
      platform: 'android',
      timeout: const Duration(milliseconds: 20),
      client: mock,
    );
    await expectLater(client.get('/x'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'TIMEOUT')));
  });
}
