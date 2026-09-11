/// A failed API call, shaped from the server's response envelope
/// `{ success, message, error, data }`.
///
/// The server's `error` field takes four shapes (see `errorHandler.js`):
/// `null`, a plain string (a 401's message, or a code like `RATE_LIMITED` /
/// `INTERNAL_ERROR`), `{ code: '...' }` (the 403 family the app routes on), or a
/// `{ field: message }` map (422 validation). This flattens them into
/// [code] + [fieldErrors] so callers never inspect raw JSON.
class ApiException implements Exception {
  /// HTTP status; 0 when the request never got a response (network / timeout).
  final int status;

  /// A machine code when the server sent one: `PASSWORD_CHANGE_REQUIRED`,
  /// `MOBILE_ACCESS_DISABLED`, `MOBILE_SCOPE`, `MOBILE_ONLY`, `ACCOUNT_INACTIVE`,
  /// `RATE_LIMITED`, `INTERNAL_ERROR`; or the client-side `NETWORK_ERROR`,
  /// `TIMEOUT`, `INVALID_ENVELOPE`.
  final String? code;

  /// The human message (the envelope's `message`, or a client-side sentence).
  final String message;

  /// 422 field map, empty otherwise.
  final Map<String, String> fieldErrors;

  const ApiException({
    required this.status,
    required this.message,
    this.code,
    this.fieldErrors = const {},
  });

  const ApiException.network(String message)
      : this(status: 0, code: 'NETWORK_ERROR', message: message);

  const ApiException.timeout(String message)
      : this(status: 0, code: 'TIMEOUT', message: message);

  bool get isUnauthorized => status == 401;
  bool get isValidation => status == 422;
  bool get isConflict => status == 409;
  bool get isNetwork => status == 0;
  bool get passwordChangeRequired => code == 'PASSWORD_CHANGE_REQUIRED';
  bool get mobileAccessDisabled => code == 'MOBILE_ACCESS_DISABLED';
  bool get accountInactive => code == 'ACCOUNT_INACTIVE';

  /// Fatal for a mobile session: the phone must go back to the login screen.
  bool get endsSession => isUnauthorized || mobileAccessDisabled || accountInactive || code == 'MOBILE_SCOPE';

  static final _codeShape = RegExp(r'^[A-Z][A-Z0-9_]+$');

  factory ApiException.fromEnvelope(int status, Map<String, dynamic> body) {
    final err = body['error'];
    String? code;
    final fields = <String, String>{};
    if (err is Map) {
      if (err['code'] is String) {
        code = err['code'] as String;
      } else {
        err.forEach((k, v) {
          if (v is String) fields['$k'] = v;
        });
      }
    } else if (err is String && _codeShape.hasMatch(err)) {
      code = err;
    }
    final message = body['message'];
    return ApiException(
      status: status,
      code: code,
      message: message is String && message.isNotEmpty ? message : 'Request failed ($status).',
      fieldErrors: fields,
    );
  }

  @override
  String toString() => 'ApiException($status${code == null ? '' : ' $code'}: $message)';
}
