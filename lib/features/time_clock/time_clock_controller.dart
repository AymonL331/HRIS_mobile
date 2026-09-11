import 'package:flutter/foundation.dart';

import '../../core/http/api_exception.dart';
import '../../core/location/location_fix.dart';
import '../../core/time/server_clock.dart';
import 'clock_api.dart';
import 'clock_models.dart';

enum ClockPhase { idle, locating, submitting }

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

/// The Time Clock's brain: the status load, the range check, the punch flow.
/// Every tap on In/Out takes a FRESH fix — a cached position is never sent.
class TimeClockController extends ChangeNotifier {
  final ClockApi api;
  final LocationFixService fixes;
  final ServerClock clock;

  bool _loading = false;
  String? _loadError;
  ClockStatus? _status;
  ClockPhase _phase = ClockPhase.idle;
  PunchOutcome? _outcome;
  LocationFix? _lastFix;
  bool _rangeChecking = false;
  bool _consentSaving = false;
  bool _disposed = false;

  TimeClockController({required this.api, required this.fixes, ServerClock? clock}) : clock = clock ?? ServerClock();

  bool get loading => _loading;
  String? get loadError => _loadError;
  ClockStatus? get status => _status;
  ClockPhase get phase => _phase;
  PunchOutcome? get outcome => _outcome;
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
    } on ApiException catch (e) {
      _loadError = e.message;
    } finally {
      _loading = false;
      _notify();
    }
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

  Future<void> punch(String direction) async {
    if (busy) return;
    _outcome = null;
    _phase = ClockPhase.locating;
    _notify();

    LocationFix fix;
    try {
      fix = await fixes.acquire();
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

    _phase = ClockPhase.submitting;
    _notify();
    try {
      final r = await api.punch(direction: direction, fix: fix);
      _outcome = PunchSuccess(r, warnLowAccuracy: warnLowAccuracy);
      if (r.serverTime != null) clock.sync(r.serverTime!);
      await load(silent: true);
    } on ApiException catch (e) {
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

  void _fail(PunchOutcome o) {
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
    super.dispose();
  }
}
