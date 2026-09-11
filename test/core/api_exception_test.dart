import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/http/api_exception.dart';

void main() {
  group('ApiException.fromEnvelope', () {
    test('401 with a string error keeps the message and no code', () {
      final e = ApiException.fromEnvelope(401, {
        'success': false,
        'message': 'Invalid company code, username/email, or password.',
        'data': null,
        'error': 'Invalid company code, username/email, or password.',
      });
      expect(e.status, 401);
      expect(e.code, isNull);
      expect(e.isUnauthorized, isTrue);
      expect(e.endsSession, isTrue);
      expect(e.message, 'Invalid company code, username/email, or password.');
      expect(e.fieldErrors, isEmpty);
    });

    test('403 with { code } exposes the code', () {
      final e = ApiException.fromEnvelope(403, {
        'success': false,
        'message': 'Mobile app access is not enabled for this account. Ask HR to enable it.',
        'data': null,
        'error': {'code': 'MOBILE_ACCESS_DISABLED'},
      });
      expect(e.code, 'MOBILE_ACCESS_DISABLED');
      expect(e.mobileAccessDisabled, isTrue);
      expect(e.endsSession, isTrue);
      expect(e.passwordChangeRequired, isFalse);
    });

    test('403 PASSWORD_CHANGE_REQUIRED does not end the session', () {
      final e = ApiException.fromEnvelope(403, {
        'success': false,
        'message': 'You must change your password before using the system.',
        'data': null,
        'error': {'code': 'PASSWORD_CHANGE_REQUIRED'},
      });
      expect(e.passwordChangeRequired, isTrue);
      expect(e.endsSession, isFalse);
    });

    test('422 with a field map fills fieldErrors and no code', () {
      final e = ApiException.fromEnvelope(422, {
        'success': false,
        'message': 'Validation failed.',
        'data': null,
        'error': {'company_code': 'Company code is required.', 'password': 'Password is required.'},
      });
      expect(e.isValidation, isTrue);
      expect(e.code, isNull);
      expect(e.fieldErrors, {
        'company_code': 'Company code is required.',
        'password': 'Password is required.',
      });
    });

    test('429 RATE_LIMITED string is read as a code', () {
      final e = ApiException.fromEnvelope(429, {
        'success': false,
        'message': 'Too many requests. Try again later.',
        'data': null,
        'error': 'RATE_LIMITED',
      });
      expect(e.code, 'RATE_LIMITED');
    });

    test('500 in production masks to INTERNAL_ERROR', () {
      final e = ApiException.fromEnvelope(500, {
        'success': false,
        'message': 'Internal Server Error',
        'data': null,
        'error': 'INTERNAL_ERROR',
      });
      expect(e.code, 'INTERNAL_ERROR');
      expect(e.message, 'Internal Server Error');
    });

    test('a missing message falls back to a status sentence', () {
      final e = ApiException.fromEnvelope(502, {'success': false, 'error': null});
      expect(e.message, 'Request failed (502).');
    });
  });
}
