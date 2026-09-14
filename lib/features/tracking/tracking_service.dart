import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../core/auth/session_controller.dart';
import '../../core/time/manila_time.dart';
import 'tracking_config.dart';
import 'tracking_models.dart';
import 'tracking_task_handler.dart';

/// What the Time Clock shows about recording, as last reported by the service.
class TrackingSnapshot {
  final bool running;
  final int? attendanceLogId;
  final DateTime? lastPointAt;
  final DateTime? lastUploadAt;
  final int queued;
  final bool uploadFailing;

  /// Why recording last stopped: `clocked_out`, `shift_closed`, `signed_out`,
  /// `consent_withdrawn`, `max_duration`, or `could_not_start`.
  final String? stopReason;

  const TrackingSnapshot({
    required this.running,
    this.attendanceLogId,
    this.lastPointAt,
    this.lastUploadAt,
    this.queued = 0,
    this.uploadFailing = false,
    this.stopReason,
  });

  static const idle = TrackingSnapshot(running: false);

  factory TrackingSnapshot.fromMessage(Map<dynamic, dynamic> m) => TrackingSnapshot(
        running: m['running'] == true,
        attendanceLogId: m['attendance_log_id'] is int ? m['attendance_log_id'] as int : null,
        lastPointAt: ManilaTime.parseUtc(m['last_point_at'] as String?),
        lastUploadAt: ManilaTime.parseUtc(m['last_upload_at'] as String?),
        queued: m['queued'] is int ? m['queued'] as int : 0,
        uploadFailing: m['upload_failing'] == true,
        stopReason: m['stop_reason'] as String?,
      );
}

/// The UI side of work-hours tracking. Abstract so the controller and the
/// screen are tested with a fake — a widget test cannot run a foreground service.
abstract class TrackingService {
  ValueListenable<TrackingSnapshot> get snapshot;

  /// Make the phone match what the SERVER says (the status `tracking` block):
  /// recording while it is active for that shift, stopped otherwise.
  Future<void> sync(TrackingState state);

  Future<void> stop({String reason = 'clocked_out'});
}

class ForegroundTrackingService implements TrackingService {
  final SessionController session;
  final ValueNotifier<TrackingSnapshot> _snapshot = ValueNotifier(TrackingSnapshot.idle);
  bool _initialized = false;
  Future<void>? _inFlight;

  ForegroundTrackingService(this.session) {
    FlutterForegroundTask.addTaskDataCallback(_onData);
  }

  @override
  ValueListenable<TrackingSnapshot> get snapshot => _snapshot;

  void _onData(Object data) {
    if (data is Map) _snapshot.value = TrackingSnapshot.fromMessage(data);
  }

  void _init() {
    if (_initialized) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'work_location',
        channelName: 'Work location recording',
        channelDescription: 'Shown while HRIS records your location between clock-in and clock-out.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false, playSound: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        // The service's minute tick: heartbeat, upload, the 16 h cap.
        eventAction: ForegroundTaskEventAction.repeat(60 * 1000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowAutoRestart: true,
        stopWithTask: false,
      ),
    );
    _initialized = true;
  }

  @override
  Future<void> sync(TrackingState state) {
    // One sync at a time: a load() while a start is still settling must not
    // start a second service or stop the one being started.
    final previous = _inFlight ?? Future<void>.value();
    final next = previous.then((_) => _sync(state)).catchError((Object e) {
      debugPrint('tracking: sync failed: $e');
    });
    _inFlight = next;
    return next;
  }

  Future<void> _sync(TrackingState state) async {
    final running = await FlutterForegroundTask.isRunningService;
    if (!state.active || state.attendanceLogId == null) {
      if (running) await _stop('shift_closed');
      return;
    }

    final current = await TrackingConfig.load();
    if (running && current?.attendanceLogId == state.attendanceLogId) {
      FlutterForegroundTask.sendDataToTask({'command': 'report'});
      return;
    }

    _init();
    final since = state.since ?? DateTime.now().toUtc();
    await TrackingConfig(
      attendanceLogId: state.attendanceLogId!,
      since: since,
      policy: state.policy,
      baseUrl: session.env.baseUrl,
      envKey: session.env.storageKey,
      appVersion: session.appVersion,
    ).save();

    final result = running
        ? await FlutterForegroundTask.restartService()
        : await FlutterForegroundTask.startService(
            serviceId: 4217,
            serviceTypes: const [ForegroundServiceTypes.location],
            notificationTitle: 'HRIS is recording your work location',
            notificationText: 'Since ${ManilaTime.time(since)}. Stops when you clock out.',
            callback: startTrackingCallback,
          );
    switch (result) {
      case ServiceRequestSuccess():
        _snapshot.value = TrackingSnapshot(running: true, attendanceLogId: state.attendanceLogId);
      case ServiceRequestFailure(:final error):
        debugPrint('tracking: could not start: $error');
        await TrackingConfig.clear();
        _snapshot.value = const TrackingSnapshot(running: false, stopReason: 'could_not_start');
    }
  }

  @override
  Future<void> stop({String reason = 'clocked_out'}) {
    final previous = _inFlight ?? Future<void>.value();
    final next = previous.then((_) => _stop(reason)).catchError((Object e) {
      debugPrint('tracking: stop failed: $e');
    });
    _inFlight = next;
    return next;
  }

  Future<void> _stop(String reason) async {
    if (!await FlutterForegroundTask.isRunningService) {
      await TrackingConfig.clear();
      _snapshot.value = TrackingSnapshot(running: false, stopReason: reason);
      return;
    }
    // The service records the stop, flushes and stops itself…
    FlutterForegroundTask.sendDataToTask({'command': 'stop', 'reason': reason});
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!await FlutterForegroundTask.isRunningService) break;
    }
    // …and if it could not, it is stopped from here: recording must end.
    if (await FlutterForegroundTask.isRunningService) {
      await TrackingConfig.clear();
      await FlutterForegroundTask.stopService();
    }
    _snapshot.value = TrackingSnapshot(running: false, stopReason: reason);
  }
}
