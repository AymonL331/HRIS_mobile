import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_env.dart';
import '../config/env_store.dart';
import '../http/api_client.dart';
import '../http/api_exception.dart';
import '../http/endpoints.dart';
import 'session_store.dart';
import 'user.dart';

/// Where the app is in its life. The root widget switches on this.
sealed class SessionState {
  const SessionState();
}

class Bootstrapping extends SessionState {
  const Bootstrapping();
}

class SignedOut extends SessionState {
  /// Why the user is looking at the login screen, when there is a reason worth
  /// showing ("Session expired", "Mobile app access has been disabled…").
  final String? reason;
  const SignedOut({this.reason});
}

class MustChangePassword extends SessionState {
  final User user;
  final Tenant? tenant;
  const MustChangePassword(this.user, this.tenant);
}

class SignedIn extends SessionState {
  final User user;
  final Tenant? tenant;
  const SignedIn(this.user, this.tenant);
}

/// The session state machine: bootstrap → login → (must change password) →
/// signed in → logout, and the policy for what a failed call means.
///
/// Owns the [ApiClient] for the current environment and rebuilds it when the
/// environment changes. Every feature goes through [guard] so the three
/// session-ending codes (401, MOBILE_ACCESS_DISABLED, ACCOUNT_INACTIVE) and the
/// forced-password-change code are handled in exactly one place.
class SessionController extends ChangeNotifier {
  final EnvStore _env;
  final SessionStore _store;
  final String appVersion;
  final http.Client? _httpClient;

  SessionState _state = const Bootstrapping();
  SessionRecord? _record;
  ApiClient? _client;
  String? _clientBaseUrl;

  SessionController({
    required this._env,
    required this._store,
    required this.appVersion,
    this._httpClient,
  }) {
    _env.addListener(_onEnvChanged);
  }

  SessionState get state => _state;
  EnvConfig get env => _env.config;
  bool get isSignedIn => _state is SignedIn;

  User? get user => switch (_state) {
        SignedIn(:final user) => user,
        MustChangePassword(:final user) => user,
        _ => null,
      };

  Tenant? get tenant => _record?.tenant;

  /// The API client for the current environment (rebuilt on a URL change).
  ApiClient get client {
    final base = _env.config.baseUrl;
    if (_client == null || _clientBaseUrl != base) {
      _client?.close();
      _client = ApiClient(
        baseUrl: base,
        tokenProvider: () async => _record?.token,
        appVersion: appVersion,
        client: _httpClient,
      );
      _clientBaseUrl = base;
    }
    return _client!;
  }

  void _onEnvChanged() => notifyListeners();

  void _set(SessionState s) {
    _state = s;
    notifyListeners();
  }

  SessionState _routeFor(User user) =>
      user.mustChangePassword ? MustChangePassword(user, _record?.tenant) : SignedIn(user, _record?.tenant);

  /// Cold start only (never on resume — `/api/auth/*` shares the auth rate
  /// limiter in production). Validates the stored token with `/auth/me`.
  Future<void> bootstrap() async {
    _set(const Bootstrapping());
    _record = await _store.read(env.storageKey);
    if (_record == null) {
      _set(const SignedOut());
      return;
    }
    try {
      final user = await client.get<User>(Endpoints.me, parse: (d) => User.fromJson(d as Map<String, dynamic>));
      // /auth/me is exempt from the server's per-request mobile check precisely
      // so the app can read the switch here: HR turned it off while the phone
      // was idle → sign out with the reason instead of failing at the first tap.
      if (!user.mobileAccessEnabled) {
        await _forget();
        _set(const SignedOut(reason: 'Mobile app access has been disabled for this account. Ask HR if you think this is a mistake.'));
        return;
      }
      _set(_routeFor(user));
    } on ApiException catch (e) {
      if (e.endsSession) {
        await _forget();
        _set(SignedOut(reason: e.isUnauthorized ? 'Your session has expired. Please sign in again.' : e.message));
      } else {
        // Server unreachable or a transient error: keep the token for the next
        // cold start, but the app needs the server to work at all.
        _set(SignedOut(reason: e.message));
      }
    }
  }

  Future<void> login({required String companyCode, required String identifier, required String password}) async {
    final data = await client.post<Map<String, dynamic>>(
      Endpoints.login,
      body: {'company_code': companyCode, 'identifier': identifier, 'password': password, 'client': 'mobile'},
      parse: (d) => d as Map<String, dynamic>,
    );
    final tenantJson = data['tenant'];
    _record = SessionRecord(
      token: data['token'] as String,
      tenant: tenantJson is Map<String, dynamic> ? Tenant.fromJson(tenantJson) : null,
    );
    await _store.write(env.storageKey, _record!);
    _set(_routeFor(User.fromJson(data['user'] as Map<String, dynamic>)));
  }

  /// The password gate is on the user row, so the SAME token keeps working
  /// once the change succeeds — mirror that locally, no re-login.
  void markPasswordChanged() {
    final u = user;
    if (u != null) _set(SignedIn(u.copyWith(mustChangePassword: false), _record?.tenant));
  }

  Future<void> logout({String? reason}) async {
    await _forget();
    _set(SignedOut(reason: reason));
  }

  /// Switching backends always drops the session: a token belongs to one
  /// environment. From the login screen there is nothing to drop.
  Future<void> switchEnv(AppEnv target) async {
    if (target == env.selected) return;
    if (_record != null) await _forget();
    await _env.select(target);
    _set(const SignedOut());
  }

  /// Run an authenticated call with the session policy applied: a
  /// forced-password code routes to the change screen; a session-ending code
  /// signs the phone out with the server's reason. The exception is rethrown
  /// either way so the caller can stop what it was doing.
  Future<T> guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on ApiException catch (e) {
      if (e.passwordChangeRequired) {
        final u = user;
        if (u != null) _set(MustChangePassword(u.copyWith(mustChangePassword: true), _record?.tenant));
      } else if (e.endsSession) {
        await logout(reason: e.isUnauthorized ? 'Your session has expired. Please sign in again.' : e.message);
      }
      rethrow;
    }
  }

  Future<void> _forget() async {
    await _store.delete(env.storageKey);
    _record = null;
  }

  @override
  void dispose() {
    _env.removeListener(_onEnvChanged);
    _client?.close();
    super.dispose();
  }
}
