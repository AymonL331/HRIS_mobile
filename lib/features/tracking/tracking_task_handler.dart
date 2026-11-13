import 'dart:async';
import 'dart:math';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/session_store.dart';
import '../../core/http/api_client.dart';
import '../../core/http/endpoints.dart';
import 'ping_queue.dart';
import 'ping_uploader.dart';
import 'tracking_config.dart';
import 'tracking_foreground.dart';
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
  final TrackingAlerts _alerts = TrackingAlerts();
  String? _lastNotice;

  /// The last "alive" minute written BEFORE this start (null = none / handled).
  DateTime? _aliveBeforeStart;

  /// Written every minute while recording; read after a reboot to say WHEN the
  /// phone went off (migration 119). `bootedAtKey` is written by the Android
  /// boot receiver (BootMarkReceiver.kt) — same SharedPreferences file.
  static const lastAliveKey = 'tracking.last_alive_at';
  static const bootedAtKey = 'tracking.booted_at';

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

    // Started by the SYSTEM (or by our watchdog) = restarted after the phone
    // killed the service or rebooted. Saying so is what lets the website label
    // the silence before it.
    final byWatchdog = await FlutterForegroundTask.getData<bool>(key: watchdogRestartKey) == true;
    if (byWatchdog) await FlutterForegroundTask.removeData(key: watchdogRestartKey);
    await _readAliveBeforeStart();
    await _notePhoneOff();
    await _event(starter == TaskStarter.system || byWatchdog ? 'resumed_after_kill' : 'start');
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
      // No fix this time (indoors, in a vehicle). Say so: a `no_fix` event carries
      // no position but tells the trail the phone was alive and simply had no sky,
      // so the gap reads "no GPS" instead of "nothing from the phone", and the
      // live map does not declare tracking lost (migration 065).
      await _event('no_fix');
    }
  }

  Future<void> _record(Position p, String kind) async {
    final c = _config;
    final q = _queue;
    if (c == null || q == null || _stopping) return;
    // A fix again: whatever was wrong is fixed — take the alert away.
    if (_locationOffNoted) unawaited(_alerts.clear(TrackingAlert.locationOff));
    if (_permissionNoted) unawaited(_alerts.clear(TrackingAlert.permissionLost));
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

  // Once per episode: a phone with location off for an hour records ONE event —
  // and the employee gets ONE "turn it back on" notification (2026-11-13).
  Future<void> _noteLocationOff() async {
    if (_locationOffNoted) return;
    _locationOffNoted = true;
    await _event('gap_location_off');
    await _alerts.show(TrackingAlert.locationOff);
  }

  Future<void> _notePermissionLost() async {
    if (_permissionNoted) return;
    _permissionNoted = true;
    await _event('gap_permission_lost');
    await _alerts.show(TrackingAlert.permissionLost);
  }

  /// After a reboot mid-shift: the boot receiver wrote when the phone started,
  /// and the last minute tick before this start says when it was last alive. A
  /// boot after that tick means the phone was OFF in between — recorded as
  /// `phone_off` at that last tick, so the gap reads "The phone was turned off".
  /// Checked at start AND on every tick until the boot mark is seen: the
  /// plugin's boot receiver may start this service before ours writes it.
  Future<void> _readAliveBeforeStart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      _aliveBeforeStart = DateTime.tryParse(prefs.getString(lastAliveKey) ?? '');
    } catch (_) {}
  }

  Future<void> _notePhoneOff() async {
    final c = _config;
    final alive = _aliveBeforeStart;
    final q = _queue;
    if (c == null || alive == null || q == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final booted = DateTime.tryParse(prefs.getString(bootedAtKey) ?? '');
      if (booted == null) return;
      await prefs.remove(bootedAtKey);
      _aliveBeforeStart = null;
      if (!alive.isAfter(c.since) || !booted.isAfter(alive)) return;
      await q.add(QueuedPing(
        uuid: newPingUuid(),
        attendanceLogId: c.attendanceLogId,
        kind: 'phone_off',
        capturedAt: alive.toUtc(),
      ));
    } catch (e) {
      debugPrint('tracking: phone-off check failed: $e');
    }
  }

  Future<void> _markAlive() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(lastAliveKey, DateTime.now().toUtc().toIso8601String());
    } catch (_) {}
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
      if (_aliveBeforeStart != null) await _notePhoneOff();
      await _markAlive();
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
    // The quiet notice (2026-11-13): the same words all shift, changed only when
    // the employee must act — so it never lights up or redraws every minute.
    final problem = _locationOffNoted
        ? 'Location is off — turn it on'
        : _permissionNoted
            ? 'Location permission is off — open ATLAS'
            : null;
    final notice = problem ?? trackingNoticeText(c.since);
    if (notice != _lastNotice) {
      _lastNotice = notice;
      await FlutterForegroundTask.updateService(notificationTitle: trackingNoticeTitle, notificationText: notice);
    }
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
    await _alerts.clearAll();
    await disarmTrackingWatchdog();
    FlutterForegroundTask.sendDataToMain({'running': false, 'stop_reason': reason});
    await FlutterForegroundTask.stopService();
  }
}
