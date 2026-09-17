import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/auth/session_controller.dart';
import '../time_clock/clock_models.dart';
import 'reminder_models.dart';
import 'reminder_scheduler.dart';
import 'reminder_store.dart';

/// What the Time Clock tells the reminders after every status load. Abstract
/// so the controller is tested with a fake, like the tracking service.
abstract class ReminderSync {
  Future<void> onStatus(ClockStatus status);
}

/// The signed-in app's side of the reminders: after every status load the
/// alarms are re-planned (a clock-in cancels today's clock-in ladder), the
/// connection the alarm callback will need is written down, and a sign-out
/// cancels everything. One operation at a time, like tracking's sync.
class ReminderCoordinator implements ReminderSync {
  final SessionController session;
  final ReminderStore store;
  final ReminderScheduler scheduler;
  Future<void>? _inFlight;

  ReminderCoordinator({required this.session, required this.store, required this.scheduler});

  Future<void> _serial(Future<void> Function() op, String what) {
    final previous = _inFlight ?? Future<void>.value();
    final next = previous.then((_) => op()).catchError((Object e) {
      debugPrint('reminders: $what failed: $e');
    });
    _inFlight = next;
    return next;
  }

  @override
  Future<void> onStatus(ClockStatus status) => _serial(() async {
        await store.saveConnection(ReminderConnection(
          baseUrl: session.env.baseUrl,
          envKey: session.env.storageKey,
          appVersion: session.appVersion,
        ));
        await scheduler.sync(status: LastStatus.fromClock(status));
      }, 'sync');

  /// Settings › "Sync now": fetch the schedule again whatever its age.
  Future<void> resync() => _serial(() => scheduler.sync(force: true), 'resync');

  Future<void> clear() => _serial(scheduler.clear, 'clear');

  Future<ReminderAlarm?> next() => scheduler.next();
}
