import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/http/api_exception.dart';
import '../../core/location/location_fix.dart';
import '../../core/time/manila_time.dart';
import '../../core/time/server_clock.dart';
import '../face/face_capture_screen.dart';
import '../face/face_models.dart';
import '../offline_clock/offline_clock_service.dart';
import '../offline_clock/offline_models.dart';
import '../reminders/reminder_coordinator.dart';
import '../tracking/phone_setup.dart';
import '../tracking/tracking_models.dart';
import '../tracking/tracking_service.dart';
import 'clock_api.dart';
import 'clock_models.dart';

enum ClockPhase { idle, locating, verifyingFace, submitting }

/// Presents the face check and returns what it produced. The controller does not
/// know how the capture is drawn — the screen pushes [FaceCaptureScreen] and the
/// tests hand back a canned result, so the punch flow is testable without a
/// camera or a WebView.
typedef FaceCapturer = Future<FaceResult> Function(String direction);

/// What the last punch attempt came to. Shown as a card until the next tap.
sealed class PunchOutcome {
  const PunchOutcome();
}

class PunchSuccess extends PunchOutcome {
  final PunchResponse response;
  final bool warnLowAccuracy;
  const PunchSuccess(this.response, {required this.warnLowAccuracy});
}

/// 409 — already clocked in / not clocked in yet. Not an error, a fact.
class PunchInfo extends PunchOutcome {
  final String message;
  const PunchInfo(this.message);
}

/// The server refused the punch on location grounds (geofence block).
class PunchBlocked extends PunchOutcome {
  final String message;
  const PunchBlocked(this.message);
}

/// Refused on the phone before anything was sent, or a server/network error.
class PunchFailure extends PunchOutcome {
  final String message;
  const PunchFailure(this.message);
}

class PunchNeedsConsent extends PunchOutcome {
  const PunchNeedsConsent();
}

/// No signal: the face matched on the phone and the punch is kept here until it
/// can be sent (offline clock-in, 2026-11-24).
class PunchSavedOffline extends PunchOutcome {
  final OfflinePunch punch;
  final bool warnLowAccuracy;
  const PunchSavedOffline(this.punch, {required this.warnLowAccuracy});
}

/// No signal and the face did not match on the phone 3 times in a row
/// (2026-11-25): the screen offers "Save for HR to check".
class PunchOfflineNoMatch extends PunchOutcome {
  final String direction;
  final List<double> tries;
  final double threshold;
  final bool showScores;
  const PunchOfflineNoMatch({required this.direction, required this.tries, required this.threshold, required this.showScores});
}

/// Refused on the phone at clock-in: a setting work-hours recording needs is
/// off (location "all the time", precise, notifications, battery). The screen
/// offers a "Fix it" button (2026-11-13).
class PunchNeedsSetup extends PunchOutcome {
  final SetupProblem problem;
  const PunchNeedsSetup(this.problem);

  String get message => problem.message;
}

/// The clock-in check: null = ready, otherwise what to fix and where.
typedef ClockInCheck = Future<SetupProblem?> Function();

/// Runs before a clock-out with the open shift's id; false = the employee
/// cancelled (e.g. the "explain your gaps" dialog).
typedef BeforeClockOut = Future<bool> Function(int attendanceLogId);

/// The Time Clock's brain: the status load, the range check, the punch flow.
/// Every tap on In/Out takes a FRESH fix — a cached position is never sent.
class TimeClockController extends ChangeNotifier {
  final ClockApi api;
  final LocationFixService fixes;
  final ServerClock clock;

  /// Work-hours location tracking. Null where there is no service to drive (a
  /// widget test that is not about tracking).
  final TrackingService? tracking;

  /// The clock-in / clock-out reminder alarms, re-planned after every status
  /// load (a clock-in cancels today's clock-in ladder). Null in tests that are
  /// not about reminders.
  final ReminderSync? reminders;

  /// Re-checked at EVERY clock-in (2026-11-13). Null in tests not about it.
  final ClockInCheck? clockInCheck;

  /// Asked before every clock-out of a recorded shift. Set by the screen, which
  /// owns the dialog's BuildContext. Null = nothing to ask.
  BeforeClockOut? beforeClockOut;

  /// OFFLINE clock-in (2026-11-24). Null = the phone never clocks offline (tests
  /// not about it).
  final OfflineClockService? offline;

  /// The last status load could not reach the server: the screen shows the last
  /// one it had and punches are kept on the phone.
  bool _offlineMode = false;
  bool get offlineMode => _offlineMode;
  final Set<String> _localNonces = <String>{};
  Timer? _retry;

  /// How many failed offline face tries in a row before "Save for HR to check".
  static const offlineTriesBeforeHr = 3;

  /// Show the face score when the offline check fails. Test builds only:
  /// `--dart-define=SHOW_FACE_SCORE=true` (2026-11-25).
  final bool showFaceScore;

  // The failed offline face tries in a row, for one direction, and the last
  // one's capture + fix (what "Save for HR to check" keeps).
  final List<double> _offlineMisses = <double>[];
  String? _missDirection;
  LocationFix? _missFix;
  FaceCapture? _missCapture;
  bool _missLowAccuracy = false;

  void _clearMisses() {
    _offlineMisses.clear();
    _missDirection = null;
    _missFix = null;
    _missCapture = null;
  }

  bool _loading = false;
  String? _loadError;
  ClockStatus? _status;
  ClockPhase _phase = ClockPhase.idle;
  PunchOutcome? _outcome;
  LocationFix? _lastFix;
  bool _rangeChecking = false;
  bool _consentSaving = false;
  bool _disposed = false;

  TimeClockController({
    required this.api,
    required this.fixes,
    ServerClock? clock,
    this.tracking,
    this.reminders,
    this.clockInCheck,
    this.beforeClockOut,
    this.offline,
    this.showFaceScore = const bool.fromEnvironment('SHOW_FACE_SCORE'),
  }) : clock = clock ?? ServerClock() {
    offline?.addListener(_notify);
  }

  bool get loading => _loading;
  String? get loadError => _loadError;
  ClockStatus? get status => _status;
  ClockPhase get phase => _phase;
  PunchOutcome? get outcome => _outcome;

  // LATE / UNDERTIME REASONS (server migration 128): what still has to be
  // explained — from the punch reply and from today's row, so a popup closed by
  // killing the app asks again on the next open. Late first, each once.
  final Set<String> _answered = <String>{};
  List<PendingReason> get pendingReasons {
    final seen = <String>{};
    final out = <PendingReason>[];
    void add(List<PendingReason> list) {
      for (final p in list) {
        if (!_answered.contains(p.key) && seen.add(p.key)) out.add(p);
      }
    }
    final o = _outcome;
    if (o is PunchSuccess) add(o.response.pendingReasons);
    add(_status?.today?.pendingReasons ?? const []);
    return [...out.where((p) => p.kind == 'late'), ...out.where((p) => p.kind != 'late')];
  }

  /// Send one reason. Throws the ApiException so the popup can show it and stay open.
  Future<void> submitReason(PendingReason p, String reason) async {
    await api.submitReason(attendanceLogId: p.attendanceLogId, kind: p.kind, reason: reason);
    _answered.add(p.key);
    _notify();
  }
  LocationFix? get lastFix => _lastFix;
  bool get rangeChecking => _rangeChecking;
  bool get consentSaving => _consentSaving;
  bool get busy => _phase != ClockPhase.idle;

  /// Distance of the last fix from the worksite, for the range chip.
  ({int? distanceM, bool? within}) get range {
    final s = _status;
    final f = _lastFix;
    if (s == null || f == null) return (distanceM: null, within: null);
    return s.worksite.measure(f.latitude, f.longitude);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      _loading = true;
      _loadError = null;
      _notify();
    }
    try {
      final s = await api.status();
      _status = s;
      clock.sync(s.serverTime);
      _loadError = null;
      _offlineMode = false;
      _syncTracking(s.tracking);
      _syncReminders(s);
      unawaited(_afterOnline(s));
    } on ApiException catch (e) {
      final cached = e.isNetwork ? await _cachedStatus() : null;
      if (cached != null) {
        // NO SIGNAL: keep (or bring back) the last screen; punches go to the phone.
        _status = _status ?? cached;
        _offlineMode = true;
        _loadError = null;
      } else {
        _loadError = e.message;
      }
    } finally {
      _loading = false;
      _armRetry();
      _notify();
    }
  }

  // Back online: remember the server time beside the phone's running clock and
  // the screen itself, send what was kept offline, refresh the face pack.
  Future<void> _afterOnline(ClockStatus s) async {
    final o = offline;
    if (o == null) return;
    await o.onServerTime(s.serverTime);
    if (s.raw != null) await o.cacheStatus(s.raw!);
    final sent = await o.sync();
    if (sent > 0 && !_disposed) await load(silent: true);
    await o.refreshKit(modelVersion: s.face.modelVersion);
  }

  // The last screen the server sent, with "today" emptied when it was another day.
  Future<ClockStatus?> _cachedStatus() async {
    final o = offline;
    if (o == null) return null;
    await o.ensureLoaded();
    final raw = await o.cachedStatus();
    if (raw == null) return null;
    final copy = Map<String, dynamic>.from(raw);
    if (copy['local_date'] != _todayLocal) copy['today'] = null;
    try {
      return ClockStatus.fromJson(copy);
    } catch (_) {
      return null;
    }
  }

  // While offline or with punches waiting, try again every minute (the moment
  // the signal is back, the waiting punches go).
  void _armRetry() {
    final waiting = _offlineMode || (offline?.pending.isNotEmpty ?? false);
    if (!waiting) {
      _retry?.cancel();
      _retry = null;
      return;
    }
    _retry ??= Timer.periodic(const Duration(seconds: 60), (_) {
      if (!busy && !_loading && !_disposed) load(silent: true);
    });
  }

  String get _todayLocal => ManilaTime.toManila(clock.nowUtc()).toIso8601String().substring(0, 10);

  /// Time In is offered: the server's day has no clock-in, and none is waiting
  /// on the phone for today.
  bool get canClockIn {
    final s = _status;
    if (s == null) return false;
    return s.canClockIn && !(offline?.hasPending('in', _todayLocal) ?? false);
  }

  /// Time Out is offered: clocked in (on the server, or on the phone today) and
  /// no clock-out waiting on the phone for today.
  bool get canClockOut {
    final s = _status;
    if (s == null) return false;
    final o = offline;
    final inToday = s.canClockOut || (o?.hasPending('in', _todayLocal) ?? false);
    return inToday && !(o?.hasPending('out', _todayLocal) ?? false);
  }

  /// The liveness challenge for a punch: the server's, or — with no signal and a
  /// face pack on the phone — one the phone picks itself.
  Future<FaceChallenge> issueChallenge(String direction) async {
    final o = offline;
    FaceChallenge local() {
      final ch = o!.localChallenge();
      _localNonces.add(ch.nonce);
      return ch;
    }

    if (_offlineMode && o?.kit != null) return local();
    try {
      return await api.faceChallenge(direction);
    } on ApiException catch (e) {
      if (e.isNetwork && o?.kit != null) {
        _offlineMode = true;
        return local();
      }
      rethrow;
    }
  }

  // Keep the punch on the phone: match the face against the phone's own pack first.
  Future<void> _saveOffline(String direction, LocationFix fix, FaceCapture capture, bool warnLowAccuracy) async {
    final o = offline;
    final kit = o?.kit;
    if (o == null || kit == null) {
      _fail(const PunchFailure(
          'No internet, and this phone does not have your face for offline use yet. Open the app once with internet, then you can clock in even without signal.'));
      return;
    }
    if (kit.modelVersion.isNotEmpty && capture.modelVersion != kit.modelVersion) {
      _fail(const PunchFailure('No internet, and the face check on this phone needs an update. Try again when you have internet.'));
      return;
    }
    final distance = kit.bestDistance(capture.embedding);
    if (distance == null || distance > kit.threshold) {
      if (_missDirection != direction) _clearMisses();
      _missDirection = direction;
      _offlineMisses.add(distance ?? 99);
      _missFix = fix;
      _missCapture = capture;
      _missLowAccuracy = warnLowAccuracy;
      if (_offlineMisses.length >= offlineTriesBeforeHr) {
        _fail(PunchOfflineNoMatch(
          direction: direction,
          tries: List.unmodifiable(_offlineMisses),
          threshold: kit.threshold,
          showScores: showFaceScore,
        ));
        return;
      }
      final score = showFaceScore && distance != null
          ? ' (score ${distance.toStringAsFixed(3)}, limit ${kit.threshold.toStringAsFixed(2)})'
          : '';
      _fail(PunchFailure('Face not recognized$score. Please try again in good light, facing the camera. '
          'Try ${_offlineMisses.length} of $offlineTriesBeforeHr.'));
      return;
    }
    _clearMisses();
    final punch = await o.save(direction: direction, fix: fix, capture: capture, phoneDistance: distance);
    _offlineMode = true;
    _outcome = PunchSavedOffline(punch, warnLowAccuracy: warnLowAccuracy);
    _phase = ClockPhase.idle;
    _armRetry();
    _notify();
    // Maybe the signal is already back.
    unawaited(load(silent: true));
  }

  /// "Save for HR to check": keep the last failed offline try (its photo, place
  /// and time) with every try's score. It goes to HR's Offline Clock-ins as
  /// Needs review and is never put on the DTR by itself.
  Future<void> saveForHr() async {
    final o = offline;
    final fix = _missFix;
    final capture = _missCapture;
    final direction = _missDirection;
    if (o == null || fix == null || capture == null || direction == null || busy) return;
    final tries = List<double>.of(_offlineMisses);
    final warn = _missLowAccuracy;
    _clearMisses();
    final punch = await o.save(
      direction: direction,
      fix: fix,
      capture: capture,
      phoneDistance: tries.isEmpty ? 99 : tries.last,
      noMatch: true,
      phoneTries: tries,
    );
    _offlineMode = true;
    _outcome = PunchSavedOffline(punch, warnLowAccuracy: warn);
    _phase = ClockPhase.idle;
    _armRetry();
    _notify();
    unawaited(load(silent: true));
  }

  /// Make the phone match the server after every status load — which follows
  /// every punch. So a clock-in starts recording, a clock-out stops it, and a
  /// cold start mid-shift (a reboot, a reinstall, a kill) picks it back up.
  /// Deliberately not awaited: stopping waits for the service's last upload,
  /// and the screen must not hang on that.
  void _syncTracking(TrackingState state) {
    final t = tracking;
    if (t == null) return;
    unawaited(t.sync(state));
  }

  /// Same shape as tracking: the status is the truth, the alarms follow it.
  /// Not awaited — it may fetch the schedule, and the screen must not wait.
  void _syncReminders(ClockStatus status) {
    final r = reminders;
    if (r == null) return;
    unawaited(r.onStatus(status));
  }

  /// The pre-punch "am I in range?" reading. Never sent anywhere.
  Future<void> checkRange() async {
    if (_rangeChecking || busy) return;
    _rangeChecking = true;
    _notify();
    try {
      _lastFix = await fixes.acquire();
    } on FixTimeout {
      _outcome = const PunchFailure("Couldn't get a GPS fix in 15 seconds. Step outside or near a window and try again.");
    } finally {
      _rangeChecking = false;
      _notify();
    }
  }

  Future<void> grantConsent() async {
    _consentSaving = true;
    _notify();
    try {
      await api.grantConsent();
      await load(silent: true);
    } on ApiException catch (e) {
      _outcome = PunchFailure(e.message);
    } finally {
      _consentSaving = false;
      _notify();
    }
  }

  /// One punch, end to end: a fresh fix, then the face check, then the write.
  ///
  /// The order is deliberate. The GPS fix is cheap and fails often (indoors, no
  /// permission, mocked), so it is taken FIRST — there is no point asking
  /// somebody to blink at a camera for twenty seconds and only then telling them
  /// their location was refused.
  ///
  /// The face check is REQUIRED (user decision 2026-09-13). There is no path
  /// through this method that submits without one, and the server refuses a
  /// punch without the face payload anyway — the gate is enforced in both
  /// places, not just here.
  Future<void> punch(String direction, {required FaceCapturer capture}) async {
    if (busy) return;
    _outcome = null;
    _phase = ClockPhase.locating;
    _notify();

    // Everything recording needs, read again now — a setting turned off since
    // the last check must not cost a whole shift of location (2026-11-13).
    final check = clockInCheck;
    if (direction == 'in' && check != null) {
      final problem = await check();
      if (problem != null) {
        _fail(PunchNeedsSetup(problem));
        return;
      }
    }
    // Long gaps on this shift need the employee's reason before clock-out.
    final shiftId = _status?.tracking.attendanceLogId;
    final ask = beforeClockOut;
    if (direction == 'out' && shiftId != null && ask != null) {
      if (!await ask(shiftId)) {
        _fail(null);
        return;
      }
    }

    // Send anything kept offline FIRST, so the server gets the day in order.
    final o = offline;
    if (!_offlineMode && o != null && o.pending.isNotEmpty) await o.sync();
    // No signal and no face pack on this phone yet: say so before the GPS wait.
    if (_offlineMode && o != null && o.kit == null) {
      _fail(const PunchFailure(
          'No internet, and this phone does not have your face for offline use yet. Open the app once with internet, then you can clock in even without signal.'));
      return;
    }

    LocationFix fix;
    try {
      // With no data the GPS finds the satellites alone, which takes longer.
      fix = await fixes.acquire(timeLimit: Duration(seconds: _offlineMode ? 45 : 15));
    } on FixTimeout {
      _fail(const PunchFailure("Couldn't get a GPS fix in 15 seconds. Step outside or near a window and try again."));
      return;
    }
    _lastFix = fix;

    final bool warnLowAccuracy;
    switch (validateFix(fix)) {
      case FixMocked():
        _fail(const PunchFailure('Mock location detected. Turn off any fake-GPS app and try again.'));
        return;
      case FixTooCoarse(:final accuracyM):
        _fail(PunchFailure('Your location is too imprecise (±${accuracyM.round()} m). Move outdoors and try again.'));
        return;
      case FixOk(warnLowAccuracy: final w):
        warnLowAccuracy = w;
    }

    // The face check. A refusal here ends the attempt — nothing is written, and
    // the reason is the employee's to act on (enrol, better light, allow the
    // camera). Cancelling is silent: they chose not to punch.
    _phase = ClockPhase.verifyingFace;
    _notify();
    final faceResult = await capture(direction);
    final FaceCapture faceCapture;
    switch (faceResult) {
      case FaceCaptured(capture: final c):
        faceCapture = c;
      case FaceFailed(reason: FaceFailure.cancelled):
        _fail(null);
        return;
      case FaceFailed(:final reason, :final serverMessage):
        _fail(PunchFailure(serverMessage ?? faceFailureMessage(reason)));
        return;
    }

    // A challenge the phone picked (no signal): the punch stays on the phone.
    if (_localNonces.remove(faceCapture.nonce)) {
      await _saveOffline(direction, fix, faceCapture, warnLowAccuracy);
      return;
    }

    _phase = ClockPhase.submitting;
    _notify();
    try {
      final r = await api.punch(direction: direction, fix: fix, capture: faceCapture);
      _outcome = PunchSuccess(r, warnLowAccuracy: warnLowAccuracy);
      if (r.serverTime != null) clock.sync(r.serverTime!);
      await load(silent: true);
    } on ApiException catch (e) {
      // The signal dropped between the face check and the send: keep it offline.
      if (e.isNetwork && offline?.kit != null) {
        await _saveOffline(direction, fix, faceCapture, warnLowAccuracy);
        return;
      }
      _outcome = switch (e) {
        _ when e.isConflict => PunchInfo(e.message),
        _ when e.fieldErrors.containsKey('location_consent') => const PunchNeedsConsent(),
        _ when e.fieldErrors.containsKey('location') => PunchBlocked(e.message),
        _ => PunchFailure(e.message),
      };
      // A 409 means the screen's idea of today was stale — refresh it.
      if (e.isConflict) await load(silent: true);
    } finally {
      _phase = ClockPhase.idle;
      _notify();
    }
  }

  /// End the attempt. A null outcome leaves no card behind — used when the
  /// employee cancelled the face check, which is a decision, not a failure.
  void _fail(PunchOutcome? o) {
    _outcome = o;
    _phase = ClockPhase.idle;
    _notify();
  }

  void dismissOutcome() {
    _outcome = null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    offline?.removeListener(_notify);
    super.dispose();
  }
}
