import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'tracking_models.dart';

/// What the tracking service needs to run, persisted by the UI before it starts
/// the service and read by the service on EVERY start — including a start by
/// the system after a reboot or a kill, when there is no UI to ask.
///
/// Holds no secret: the token is read from secure storage by env key, exactly as
/// the session store keeps it.
class TrackingConfig {
  final int attendanceLogId;
  final DateTime since;
  final TrackingPolicy policy;
  final String baseUrl;
  final String envKey;
  final String appVersion;

  const TrackingConfig({
    required this.attendanceLogId,
    required this.since,
    required this.policy,
    required this.baseUrl,
    required this.envKey,
    required this.appVersion,
  });

  static const _logId = 'tracking.attendance_log_id';
  static const _since = 'tracking.since';
  static const _distance = 'tracking.distance_filter_m';
  static const _interval = 'tracking.min_interval_s';
  static const _heartbeat = 'tracking.heartbeat_s';
  static const _maxHours = 'tracking.max_shift_hours';
  static const _baseUrl = 'tracking.base_url';
  static const _envKey = 'tracking.env_key';
  static const _appVersion = 'tracking.app_version';

  static const _keys = [_logId, _since, _distance, _interval, _heartbeat, _maxHours, _baseUrl, _envKey, _appVersion];

  Future<void> save() async {
    await FlutterForegroundTask.saveData(key: _logId, value: attendanceLogId);
    await FlutterForegroundTask.saveData(key: _since, value: since.toUtc().toIso8601String());
    await FlutterForegroundTask.saveData(key: _distance, value: policy.distanceFilterM);
    await FlutterForegroundTask.saveData(key: _interval, value: policy.minIntervalS);
    await FlutterForegroundTask.saveData(key: _heartbeat, value: policy.heartbeatS);
    await FlutterForegroundTask.saveData(key: _maxHours, value: policy.maxShiftHours);
    await FlutterForegroundTask.saveData(key: _baseUrl, value: baseUrl);
    await FlutterForegroundTask.saveData(key: _envKey, value: envKey);
    await FlutterForegroundTask.saveData(key: _appVersion, value: appVersion);
  }

  /// Null when nothing (or only part of it) is stored — the service then stops
  /// rather than guess which shift it is recording.
  static Future<TrackingConfig?> load() async {
    final logId = await FlutterForegroundTask.getData<int>(key: _logId);
    final since = await FlutterForegroundTask.getData<String>(key: _since);
    final baseUrl = await FlutterForegroundTask.getData<String>(key: _baseUrl);
    final envKey = await FlutterForegroundTask.getData<String>(key: _envKey);
    if (logId == null || since == null || baseUrl == null || envKey == null) return null;
    const d = TrackingPolicy();
    return TrackingConfig(
      attendanceLogId: logId,
      since: DateTime.tryParse(since)?.toUtc() ?? DateTime.now().toUtc(),
      policy: TrackingPolicy(
        distanceFilterM: await FlutterForegroundTask.getData<int>(key: _distance) ?? d.distanceFilterM,
        minIntervalS: await FlutterForegroundTask.getData<int>(key: _interval) ?? d.minIntervalS,
        heartbeatS: await FlutterForegroundTask.getData<int>(key: _heartbeat) ?? d.heartbeatS,
        maxShiftHours: await FlutterForegroundTask.getData<int>(key: _maxHours) ?? d.maxShiftHours,
      ),
      baseUrl: baseUrl,
      envKey: envKey,
      appVersion: await FlutterForegroundTask.getData<String>(key: _appVersion) ?? '0.0.0',
    );
  }

  static Future<void> clear() async {
    for (final k in _keys) {
      await FlutterForegroundTask.removeData(key: k);
    }
  }
}
