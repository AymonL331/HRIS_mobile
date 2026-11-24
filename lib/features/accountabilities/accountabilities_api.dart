import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/auth/session_controller.dart';
import '../../core/http/api_exception.dart';
import 'accountabilities_models.dart';

/// My Accountabilities (server migration 103) — the web's
/// accountabilityService.listMine / myPhoto: GET /api/me/accountabilities and
/// GET /api/me/accountabilities/:itemId/photos/:field (the photo bytes, private,
/// bearer-authenticated). Read-only; passwords never reach the employee.
abstract class AccountabilitiesApi {
  Future<MyAccountabilities> listMine();

  /// The photo's bytes for one item's photo field.
  Future<Uint8List> photo(int itemId, String field);
}

class MobileAccountabilitiesApi implements AccountabilitiesApi {
  static const listPath = '/api/me/accountabilities';
  static String photoPath(int itemId, String field) =>
      '/api/me/accountabilities/$itemId/photos/${Uri.encodeComponent(field)}';

  final SessionController session;
  final http.Client? httpClient;

  const MobileAccountabilitiesApi(this.session, {this.httpClient});

  @override
  Future<MyAccountabilities> listMine() => session.guard(() => session.client.get(
        listPath,
        parse: (d) => MyAccountabilities.fromJson((d as Map<String, dynamic>?) ?? const {}),
      ));

  /// The API client only speaks the JSON envelope, so the binary photo is read
  /// here with the same headers (bearer token, User-Agent, ngrok bypass). A
  /// failure is an [ApiException] so the session policy (401 → sign out) holds.
  @override
  Future<Uint8List> photo(int itemId, String field) => session.guard(() async {
        final client = httpClient ?? http.Client();
        try {
          final uri = Uri.parse('${session.env.baseUrl}${photoPath(itemId, field)}');
          final token = session.token;
          final res = await client.get(uri, headers: {
            'ngrok-skip-browser-warning': 'true',
            'User-Agent': session.client.userAgent,
            'X-App-Version': session.client.appVersion,
            if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
          }).timeout(const Duration(seconds: 20));
          if (res.statusCode != 200) {
            throw ApiException(status: res.statusCode, message: 'Could not load the photo.');
          }
          return res.bodyBytes;
        } on SocketException catch (_) {
          throw const ApiException.network('Cannot reach the server. Check your connection and the server address.');
        } on TimeoutException catch (_) {
          throw const ApiException.timeout('The server took too long to respond. Try again.');
        } finally {
          if (httpClient == null) client.close();
        }
      });
}
