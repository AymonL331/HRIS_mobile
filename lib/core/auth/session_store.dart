import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'user.dart';

/// What survives an app restart: the bearer token and the tenant it was issued
/// for. Stored PER ENVIRONMENT (the key suffix is [EnvConfig.storageKey]) so a
/// Sandbox session can never be replayed against Main.
class SessionRecord {
  final String token;
  final Tenant? tenant;

  const SessionRecord({required this.token, this.tenant});

  Map<String, dynamic> toJson() => {'token': token, 'tenant': tenant?.toJson()};

  static SessionRecord? fromJson(String raw) {
    try {
      final j = jsonDecode(raw);
      if (j is! Map<String, dynamic> || j['token'] is! String) return null;
      final t = j['tenant'];
      return SessionRecord(
        token: j['token'] as String,
        tenant: t is Map<String, dynamic> ? Tenant.fromJson(t) : null,
      );
    } catch (_) {
      return null;
    }
  }
}

abstract class SessionStore {
  Future<SessionRecord?> read(String envKey);
  Future<void> write(String envKey, SessionRecord record);
  Future<void> delete(String envKey);
}

/// The real store: the platform keystore through flutter_secure_storage.
class SecureSessionStore implements SessionStore {
  final FlutterSecureStorage _storage;

  SecureSessionStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  String _key(String envKey) => 'session.$envKey';

  @override
  Future<SessionRecord?> read(String envKey) async {
    try {
      final raw = await _storage.read(key: _key(envKey));
      return raw == null ? null : SessionRecord.fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String envKey, SessionRecord record) =>
      _storage.write(key: _key(envKey), value: jsonEncode(record.toJson()));

  @override
  Future<void> delete(String envKey) => _storage.delete(key: _key(envKey));
}

/// Tests and previews.
class InMemorySessionStore implements SessionStore {
  final Map<String, SessionRecord> _records = {};

  @override
  Future<SessionRecord?> read(String envKey) async => _records[envKey];

  @override
  Future<void> write(String envKey, SessionRecord record) async => _records[envKey] = record;

  @override
  Future<void> delete(String envKey) async => _records.remove(envKey);
}
