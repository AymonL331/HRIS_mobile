import 'dart:async';

import 'package:geolocator/geolocator.dart';
// Prefixed deliberately: permission_handler and geolocator both export a
// `ServiceStatus`, and an unprefixed double import is an ambiguity waiting to
// happen the first time someone references it.
import 'package:permission_handler/permission_handler.dart' as ph;

/// Why the app is (or is not) allowed to run right now.
enum GateVerdict {
  ok,
  serviceOff,
  permissionDenied,
  permissionDeniedForever,

  /// Location is granted, but only WHILE THE APP IS OPEN. The app requires
  /// "Allow all the time" (user decision 2026-09-14).
  backgroundDenied,

  /// Granted all the time, but set to "Approximate".
  reducedAccuracy;

  bool get blocks => this != GateVerdict.ok;
}

/// The one decision, pure so it is testable as a truth table.
///
/// The company rule is "the app does not work without location", and since
/// 2026-09-14 that means the STRICTEST grant Android offers: the device's
/// location service on, permission held as **`always`** ("Allow all the time"),
/// and accuracy **PRECISE**. Everything else blocks — Approximate, "While using
/// the app", "Only this time" and "Don't allow" alike — because the app has to
/// keep working when it is closed.
///
/// PRECEDENCE. A foreground-only grant returns [GateVerdict.backgroundDenied]
/// **whatever the accuracy is**, so each verdict names exactly one remediable
/// state: `backgroundDenied` = "you have not given Allow all the time" (and its
/// copy also tells you to turn Precise on, since both switches live on the same
/// Settings page), while `reducedAccuracy` = "you HAVE given Allow all the time
/// but left it Approximate" — one toggle, no ambiguity. Deciding it the other
/// way round would make `reducedAccuracy` mean two different situations needing
/// two different instructions.
///
/// Two deliberate lenient spots:
///  - `accuracy == unknown` PASSES. It only arises when the platform call throws
///    or on a non-Android host; below Android 12 there is no Approximate to pick.
///  - Below Android 10 there is no background permission at all, and geolocator
///    reports `always` as soon as fine/coarse is held — so minSdk 24-28 devices
///    satisfy this rule automatically and nothing regresses for them.
GateVerdict decideGate({
  required bool serviceEnabled,
  required LocationPermission permission,
  required LocationAccuracyStatus accuracy,
}) {
  if (!serviceEnabled) return GateVerdict.serviceOff;
  switch (permission) {
    case LocationPermission.deniedForever:
      return GateVerdict.permissionDeniedForever;
    case LocationPermission.denied:
    case LocationPermission.unableToDetermine:
      return GateVerdict.permissionDenied;
    case LocationPermission.whileInUse:
      // Foreground-only is no longer enough, at any accuracy.
      return GateVerdict.backgroundDenied;
    case LocationPermission.always:
      break;
  }
  if (accuracy == LocationAccuracyStatus.reduced) return GateVerdict.reducedAccuracy;
  return GateVerdict.ok;
}

/// Gathers the three inputs and opens the two settings pages. Abstract so the
/// gate widget can be tested with a scripted fake.
abstract class LocationGateService {
  /// Checks service, permission and accuracy, then returns the verdict.
  ///
  /// [interactive] says whether this check may raise the system permission
  /// dialogs. TRUE for a check the user caused (first mount, "Try again"); FALSE
  /// for a passive re-check (the app resumed), which must only observe. Getting
  /// this wrong is how you build a loop: the app re-checks on every resume, and
  /// returning from Settings IS a resume, so a prompting resume-check would
  /// bounce the user straight back out again.
  Future<GateVerdict> check({bool interactive = false});

  Future<void> openLocationSettings();

  Future<void> openAppSettings();
}

class GeolocatorGateService implements LocationGateService {
  GeolocatorGateService();

  /// "Android has told us it will not ask again."
  ///
  /// This has to be remembered, because it CANNOT be re-read. Geolocator's
  /// `checkPermission()` only ever returns denied / whileInUse / always — there
  /// is no `deniedForever` in it; that verdict can only be learned from a
  /// REQUEST. So without this flag the sequence observed on a device was:
  ///
  ///   mount   (interactive) -> deniedForever  -> the Settings screen, correct
  ///   resume  (passive)     -> denied         -> OVERWRITES it, back to "Try
  ///                                              again", which does nothing
  ///
  /// and since a resume fires immediately after the request, the employee only
  /// ever saw the dead Try again button. Once set, a passive re-check may not
  /// downgrade it; it is cleared the moment the permission actually improves.
  bool _androidWillNotAsk = false;

  @override
  Future<GateVerdict> check({bool interactive = false}) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    var permission = await Geolocator.checkPermission();

    // Anything other than `denied` is real news: the grant changed (usually in
    // Settings), so forget what we knew.
    if (permission != LocationPermission.denied) _androidWillNotAsk = false;

    // A passive re-check cannot rediscover `deniedForever`, so preserve it.
    if (!interactive && permission == LocationPermission.denied && _androidWillNotAsk) {
      permission = LocationPermission.deniedForever;
    }

    // (1) FOREGROUND — only when nothing is decided yet.
    //
    // DO NOT relax this condition. Now that ACCESS_BACKGROUND_LOCATION is in the
    // manifest, geolocator's own requestPermission() (PermissionManager.java)
    // appends BACKGROUND to the same requestPermissions() call whenever the
    // current status is already `whileInUse` — and Android 11+ SILENTLY IGNORES
    // a request that mixes foreground and background location, granting neither
    // and showing no dialog. Calling it only from `denied` keeps that branch
    // unreachable. The background ask below is a separate, isolated request.
    if (interactive && permission == LocationPermission.denied) {
      permission = await _requestForeground();
    }

    // (2) BACKGROUND — a separate request, and only once foreground is held.
    //
    // Via permission_handler, which asks for ACCESS_BACKGROUND_LOCATION ALONE —
    // the only shape Android 11+ accepts. On API 30+ this commonly shows no
    // dialog at all (it returns denied, or routes to Settings), which is why the
    // blocked screen — not this call — is what actually gets most people to
    // "Allow all the time". Never called on a passive re-check.
    if (interactive && permission == LocationPermission.whileInUse) {
      try {
        // Timed out for the same reason as the foreground ask: a permission
        // future that never completes must never be able to wedge the gate.
        await ph.Permission.locationAlways.request().timeout(const Duration(seconds: 60));
      } catch (_) {
        // A refusing or hanging platform channel must not brick the gate; the
        // re-read below simply reports whatever is actually true.
      }
      permission = await Geolocator.checkPermission();
    }

    var accuracy = LocationAccuracyStatus.unknown;
    if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
      try {
        accuracy = await Geolocator.getLocationAccuracy();
      } catch (_) {
        accuracy = LocationAccuracyStatus.unknown;
      }
    }
    return decideGate(serviceEnabled: serviceEnabled, permission: permission, accuracy: accuracy);
  }

  /// Ask for foreground location, defending against the two ways this can leave
  /// the gate stuck rather than merely refused.
  ///
  /// THE BUG THIS EXISTS FOR (seen on a device, 2026-09-14): when Android
  /// declines to show the dialog at all — which is what it does once a
  /// permission has been permanently denied — `requestPermissions()` comes back
  /// with an EMPTY grantResults array. geolocator logs
  /// "The grantResults array is empty" and returns early **without invoking its
  /// result callback**, so the Dart future from `Geolocator.requestPermission()`
  /// NEVER COMPLETES. The gate's re-entrancy guard then stays raised and every
  /// later tap of "Try again" does nothing at all. The screen looks frozen.
  ///
  /// Two defences, because either alone is not enough:
  ///  1. Ask permission_handler FIRST whether the permission is permanently
  ///     denied. It reads `shouldShowRequestPermissionRationale`, which is the
  ///     signal geolocator's `checkPermission()` cannot report — it only ever
  ///     returns denied / whileInUse / always. If Android will not ask, we do
  ///     not ask: we return `deniedForever` so the employee gets the screen with
  ///     the Settings button instead of a Try again that cannot work.
  ///  2. Even then, TIME OUT the request. A future that never completes must
  ///     never be able to wedge the gate again, whatever a future plugin
  ///     version does.
  Future<LocationPermission> _requestForeground() async {
    LocationPermission result;
    try {
      result = await Geolocator.requestPermission().timeout(const Duration(seconds: 30));
    } on TimeoutException {
      // The request never resolved — the empty-grantResults case above. Read the
      // truth instead of waiting on a future that will never complete.
      result = await Geolocator.checkPermission();
    } catch (_) {
      result = await Geolocator.checkPermission();
    }
    if (result != LocationPermission.denied) return result;

    // We asked and were refused. CAN WE ASK AGAIN? This is the question that
    // matters, and it can only be answered HERE — after a request. Android's
    // `shouldShowRequestPermissionRationale` is false both when a permission is
    // permanently denied AND when it has never been asked for, so consulting it
    // BEFORE asking cannot tell those apart. After asking, the ambiguity is
    // gone: false now means Android will not show the dialog again.
    //
    // Without this the gate sat on "Allow location access" forever — every tap
    // of Try again re-ran a request the OS silently refused, and the screen
    // re-rendered the identical verdict, which reads to the employee as a dead
    // button.
    try {
      final canAskAgain = await ph.Permission.locationWhenInUse.shouldShowRequestRationale
          .timeout(const Duration(seconds: 5));
      if (canAskAgain) return LocationPermission.denied;
      _androidWillNotAsk = true;
      return LocationPermission.deniedForever;
    } catch (_) {
      // If we cannot tell, send them to Settings: it always works, whereas a
      // retry might not.
      _androidWillNotAsk = true;
      return LocationPermission.deniedForever;
    }
  }

  @override
  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  @override
  Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }
}
