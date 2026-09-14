import 'dart:async';
import 'dart:math';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/auth/session_store.dart';
import '../../core/http/api_client.dart';
import '../../core/http/endpoints.dart';
import '../../core/time/manila_time.dart';
import 'ping_queue.dart';
import 'ping_uploader.dart';
import 'tracking_config.dart';
import 'tracking_models.dart';

/// The service's entry point. Top-level and kept by `vm:entry-point` because
/// the plugin calls it by handle from a fresh Flutter engine.
@pragma('vm:entry-point')
void startTrackingCallback() {
  FlutterForegroundTask.setTaskHandler(TrackingTaskHandler());
}

/// WORK-HOURS LOCATION TRACKING — runs inside the foreground service, in its
/// own isolate, from clock-in to clock-out (user decision 2026-09-14).
///
/// It owns the whole pipeline on its own, because it must keep working with the
/// app swiped away and the screen off:
///   position stream (moved ≥ distance filter, ≥ min interval apart)
///   + a heartbeat fix when nothing was recorded for `heartbeat_s`
///   → the offline queue (sqflite) → batched upload every 2 min or 20 points.
///
/// GAPS EXPLAIN THEMSELVES. Location switched off, the permission taken away,
/// or a restart by the system after a kill are recorded as EVENTS, so the trail
/// on the website says why it is silent instead of drawing a straight line.
///
/// IT STOPS ITSELF when the server says the shift is closed (a clock-out here or
/// anywhere else), the session ended, consent was withdrawn, or the shift passed
/// the maximum length — it never depends on the UI being alive to be told.
class TrackingTaskHandler extends TaskHandler {
  static const _uploadEvery = Duration(minutes: 2);
  static const _uploadWhenQueued = 20;
  static const _backoffMinutes = [2, 4, 8, 16, 30];

  TrackingConfig? _config;
  PingQueue? _queue;
  PingUploader? _uploader;
  ApiClient? _client;
  StreamSubscription<Position>? _positions;
  final Battery _battery = Battery();

  DateTime? _lastQueuedAt;
  DateTime? _lastPointAt;
  DateTime? _lastUploadAt;
  DateTime? _nextUploadAfter;
  int _failures = 0;
  bool _locationOffNoted = false;
  bool _permissionNoted = false;
  bool _stopping = false;
  bool _ticking = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final config = await TrackingConfig.load();
    if (config == null) {
      await FlutterForegroundTask.stopService();
      return;
    }
    _config = config;
    _queue = await SqflitePingQueue.open();
    final store = SecureSessionStore();
    _client = ApiClient(
      baseUrl: config.baseUrl,
      appVersion: config.appVersion,
      tokenProvider: () async => (await store.read(config.envKey))?.token,
    );
    _uploader = PingUploader(
      queue: _queue!,
      post: (body) => _client!.post<Map<String, dynamic>>(
        Endpoints.trackingPings,
        body: body,
        parse: (d) => (d as Map).cast<String, dynamic>(),
      ),
    );

    // Started by the SYSTEM = restarted after the phone killed the service or
    // rebooted. Saying so is what lets the website label the silence before it.
    await _event(starter == TaskStarter.system ? 'resumed_after_kill' : 'start');
    await _startPositions();
    await _tick();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_tick());
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;
    switch (data['command']) {
      case 'stop':
        unawaited(_finish((data['reason'] as String?) ?? 'clocked_out'));
      case 'flush':
        _nextUploadAfter = null;
        _lastUploadAt = null;
        unawaited(_tick());
      case 'report':
        unawaited(_report());
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _positions?.cancel();
    _positions = null;
    // No flush here: destroy gets seconds, and the queue survives for next start.
    await _queue?.close();
    _client?.close();
  }

  // --- recording ---------------------------------------------------------------

  Future<void> _startPositions() async {
    await _positions?.cancel();
    _positions = null;
    final c = _config;
    if (c == null || _stopping) return;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        await _noteLocationOff();
        return;
      }
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) {
        await _notePermissionLost();
        return;
      }
    } catch (e) {
      debugPrint('tracking: cannot read location state: $e');
      return;
    }
    _positions = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: c.policy.distanceFilterM,
        intervalDuration: Duration(seconds: c.policy.minIntervalS),
      ),
    ).listen(
      (p) => unawaited(_record(p, 'ping')),
      onError: (Object e) {
        _positions = null;
        if (e is LocationServiceDisabledException) {
          unawaited(_noteLocationOff());
        } else if (e is PermissionDeniedException) {
          unawaited(_notePermissionLost());
        }
      },
      cancelOnError: true,
    );
  }

  Future<void> _heartbeat() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        await _noteLocationOff();
        return;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: AndroidSettings(accuracy: LocationAccuracy.best, timeLimit: const Duration(seconds: 30)),
      );
      await _record(p, 'heartbeat');
    } on LocationServiceDisabledException {
      await _noteLocationOff();
    } on PermissionDeniedException {
      await _notePermissionLost();
    } catch (_) {
      // No fix this time (deep indoors). The trail shows the silence as a gap.
    }
  }

  Future<void> _record(Position p, String kind) async {
    final c = _config;
    final q = _queue;
    if (c == null || q == null || _stopping) return;
    _locationOffNoted = false;
    _permissionNoted = false;
    await q.add(QueuedPing(
      uuid: newPingUuid(),
      attendanceLogId: c.attendanceLogId,
      kind: kind,
      capturedAt: p.timestamp,
      latitude: p.latitude,
      longitude: p.longitude,
      accuracyM: p.accuracy,
      altitudeM: p.altitude,
      speedMps: p.speed,
      headingDeg: p.heading,
      isMocked: p.isMocked,
      batteryPct: await _batteryPct(),
    ));
    final now = DateTime.now().toUtc();
    _lastQueuedAt = now;
    _lastPointAt = now;
  }

  Future<void> _event(String kind) async {
    final c = _config;
    final q = _queue;
    if (c == null || q == null) return;
    await q.add(QueuedPing(
      uuid: newPingUuid(),
      attendanceLogId: c.attendanceLogId,
      kind: kind,
      capturedAt: DateTime.now().toUtc(),
      batteryPct: await _batteryPct(),
    ));
    _lastQueuedAt = DateTime.now().toUtc();
  }

  // Once per episode: a phone with location off for an hour records ONE event.
  Future<void> _noteLocationOff() async {
    if (_locationOffNoted) return;
    _locationOffNoted = true;
    await _event('gap_location_off');
  }

  Future<void> _notePermissionLost() async {
    if (_permissionNoted) return;
    _permissionNoted = true;
    await _event('gap_permission_lost');
  }

  Future<int?> _batteryPct() async {
    try {
      return await _battery.batteryLevel;
    } catch (_) {
      return null;
    }
  }

  // --- the minute tick -------------------------------------------------------------

  Future<void> _tick() async {
    if (_ticking || _stopping || _config == null) return;
    _ticking = true;
    try {
      final c = _config!;
      final now = DateTime.now().toUtc();
      if (now.difference(c.since) > Duration(hours: c.policy.maxShiftHours)) {
        await _finish('max_duration');
        return;
      }
      if (_positions == null) await _startPositions();
      if (_lastQueuedAt == null || now.difference(_lastQueuedAt!) >= Duration(seconds: c.policy.heartbeatS)) {
        await _heartbeat();
      }
      final queued = await _queue!.count();
      final allowed = _nextUploadAfter == null || now.isAfter(_nextUploadAfter!);
      final wanted = queued >= _uploadWhenQueued || _lastUploadAt == null || now.difference(_lastUploadAt!) >= _uploadEvery;
      if (queued > 0 && allowed && wanted) await _upload();
      if (!_stopping) await _report();
    } catch (e) {
      debugPrint('tracking: tick failed: $e');
    } finally {
      _ticking = false;
    }
  }

  Future<void> _upload() async {
    final c = _config!;
    final r = await _uploader!.flush();
    final now = DateTime.now().toUtc();
    if (r.retryLater) {
      _failures += 1;
      _nextUploadAfter = now.add(Duration(minutes: _backoffMinutes[min(_failures - 1, _backoffMinutes.length - 1)]));
      return;
    }
    _failures = 0;
    _nextUploadAfter = null;
    _lastUploadAt = now;
    switch (r.stop) {
      case UploadStop.sessionEnded:
        await _finish('signed_out', flush: false);
        return;
      case UploadStop.consentWithdrawn:
        await _finish('consent_withdrawn', flush: false);
        return;
      case UploadStop.none:
        break;
    }
    if (r.activeByShift[c.attendanceLogId] == false) await _finish('shift_closed');
  }

  Future<void> _report() async {
    final c = _config;
    if (c == null) return;
    final queued = await _queue?.count() ?? 0;
    final last = _lastPointAt;
    final text = [
      'Since ${ManilaTime.time(c.since)}',
      last != null ? 'last point ${ManilaTime.time(last)}' : 'waiting for GPS',
      if (queued > 0) '$queued waiting to upload',
    ].join(' · ');
    await FlutterForegroundTask.updateService(
      notificationTitle: 'HRIS is recording your work location',
      notificationText: text,
    );
    FlutterForegroundTask.sendDataToMain({
      'running': true,
      'attendance_log_id': c.attendanceLogId,
      'since': c.since.toIso8601String(),
      'last_point_at': last?.toIso8601String(),
      'last_upload_at': _lastUploadAt?.toIso8601String(),
      'queued': queued,
      'upload_failing': _failures > 0,
    });
  }

  /// End recording. [flush]: record the stop and try one last upload first
  /// (skipped when the session or consent is gone — it could not be accepted).
  Future<void> _finish(String reason, {bool flush = true}) async {
    if (_stopping) return;
    _stopping = true;
    await _positions?.cancel();
    _positions = null;
    if (flush) {
      final wasStopping = _stopping;
      _stopping = false; // let the stop event itself be queued
      await _event('stop');
      _stopping = wasStopping;
      try {
        await _uploader?.flush().timeout(const Duration(seconds: 15));
      } catch (_) {
        // Whatever did not go now stays queued for the next shift's service.
      }
    }
    await TrackingConfig.clear();
    FlutterForegroundTask.sendDataToMain({'running': false, 'stop_reason': reason});
    await FlutterForegroundTask.stopService();
  }
}
