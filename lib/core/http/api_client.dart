import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_exception.dart';

typedef TokenProvider = Future<String?> Function();
typedef UnauthorizedHandler = void Function(String? message);

/// The one HTTP door to the HRIS API.
///
/// Adds the bearer token, the ngrok interstitial bypass and the app's
/// User-Agent (which the server records in `audit_logs.user_agent` — the app's
/// provenance without a schema column), parses the response envelope, and turns
/// every failure into an [ApiException]. Session policy (what to do on a 401 or
/// a `MOBILE_ACCESS_DISABLED`) is NOT decided here — the session controller
/// wraps calls for that; this only reports [onUnauthorized] so a stale token
/// is dropped exactly once.
class ApiClient {
  final String baseUrl;
  final TokenProvider tokenProvider;
  final UnauthorizedHandler? onUnauthorized;
  final String appVersion;
  final String platform;
  final Duration timeout;
  final http.Client _client;

  ApiClient({
    required this.baseUrl,
    required this.tokenProvider,
    required this.appVersion,
    this.onUnauthorized,
    String? platform,
    this.timeout = const Duration(seconds: 20),
    http.Client? client,
  })  : platform = platform ?? Platform.operatingSystem,
        _client = client ?? http.Client();

  String get userAgent => 'HRISMobile/$appVersion ($platform)';

  Future<T> get<T>(String path, {Map<String, String>? query, T Function(dynamic data)? parse}) =>
      request('GET', path, query: query, parse: parse);

  Future<T> post<T>(String path, {Object? body, T Function(dynamic data)? parse}) =>
      request('POST', path, body: body ?? const {}, parse: parse);

  Future<T> delete<T>(String path, {T Function(dynamic data)? parse}) => request('DELETE', path, parse: parse);

  /// Returns the envelope's `data` (through [parse] when given). Throws
  /// [ApiException] for any non-2xx status, `success: false`, a body that is
  /// not the envelope (an ngrok interstitial, a wrong URL), a network failure or
  /// a timeout.
  Future<T> request<T>(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    T Function(dynamic data)? parse,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final token = await tokenProvider();
    final req = http.Request(method, uri)
      ..headers['Accept'] = 'application/json'
      ..headers['ngrok-skip-browser-warning'] = 'true'
      ..headers['User-Agent'] = userAgent
      ..headers['X-App-Version'] = appVersion;
    if (token != null && token.isNotEmpty) req.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }

    http.Response res;
    try {
      res = await _client.send(req).then(http.Response.fromStream).timeout(timeout);
    } on SocketException catch (_) {
      throw const ApiException.network('Cannot reach the server. Check your connection and the server address.');
    } on http.ClientException catch (_) {
      throw const ApiException.network('Cannot reach the server. Check your connection and the server address.');
    } on TimeoutException catch (_) {
      throw const ApiException.timeout('The server took too long to respond. Try again.');
    }

    Map<String, dynamic>? envelope;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic> && decoded['success'] is bool) envelope = decoded;
    } catch (_) {
      envelope = null;
    }
    if (envelope == null) {
      throw ApiException(
        status: res.statusCode,
        code: 'INVALID_ENVELOPE',
        message: 'Unexpected response from ${uri.host} (${res.statusCode}). Check the server address.',
      );
    }

    if (res.statusCode == 401) onUnauthorized?.call(envelope['message'] as String?);
    if (res.statusCode >= 400 || envelope['success'] == false) {
      throw ApiException.fromEnvelope(res.statusCode, envelope);
    }
    final data = envelope['data'];
    return parse == null ? data as T : parse(data);
  }

  void close() => _client.close();
}
