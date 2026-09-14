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

/// Reads the verdict, and raises the permission prompts ONLY when asked to.
/// Abstract so the setup wizard can be tested with a scripted fake.
///
/// CHECKING NEVER PROMPTS (2026-09-14, the setup wizard). The gate used to raise
/// the location dialog the moment a signed-in employee arrived, before any
/// explanation, and then chain the "all the time" request — which on Android
/// 11+ opens Settings with no instruction at all. Now [check] only observes, and
/// each prompt is its own method, called only from the button that sits under
/// the explanation of what is about to appear.
abstract class LocationGateService {
  /// Service, permission and accuracy → verdict. Never raises a dialog, so it
  /// is safe on mount and on every resume (returning from Settings IS a resume).
  Future<GateVerdict> check();

  /// The first location dialog (foreground: Precise/Approximate + While using /
  /// Only this time / Don't allow). Only meaningful while undecided.
  Future<GateVerdict> requestForeground();

  /// Gets the employee to "Allow all the time" (and "Use precise location"):
  /// the Android 11+ Location-permission page, or App info when Android has
  /// stopped routing there.
  Future<GateVerdict> requestBackground();

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
  ///   request            -> deniedForever  -> the Settings screen, correct
  ///   resume  (passive)  -> denied         -> OVERWRITES it, back to a button
  ///                                           that can never work
  ///
  /// Once set, a passive check may not downgrade it; it is cleared the moment
  /// the permission actually improves.
  bool _androidWillNotAsk = false;

  bool _requestingForeground = false;

  @override
  Future<GateVerdict> check() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    var permission = await Geolocator.checkPermission();

    // Anything other than `denied` is real news: the grant changed (usually in
    // Settings), so forget what we knew.
    if (permission != LocationPermission.denied) _androidWillNotAsk = false;

    // A passive check cannot rediscover `deniedForever`, so preserve it.
    if (permission == LocationPermission.denied && _androidWillNotAsk) {
      permission = LocationPermission.deniedForever;
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

  @override
  Future<GateVerdict> requestForeground() async {
    // A double tap must not start a second request while the dialog is up.
    if (_requestingForeground) return check();
    _requestingForeground = true;
    try {
      // DO NOT relax this condition. Now that ACCESS_BACKGROUND_LOCATION is in
      // the manifest, geolocator's own requestPermission() (PermissionManager
      // .java) appends BACKGROUND to the same requestPermissions() call whenever
      // the current status is already `whileInUse` — and Android 11+ SILENTLY
      // IGNORES a request that mixes foreground and background location,
      // granting neither and showing no dialog. Calling it only from `denied`
      // keeps that branch unreachable; background is [requestBackground].
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && !_androidWillNotAsk) {
        await _requestForeground();
      }
    } finally {
      _requestingForeground = false;
    }
    return check();
  }

  @override
  Future<GateVerdict> requestBackground() async {
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.whileInUse) {
      // Blocked for good, or Always already held but Approximate: no request
      // can fix either. The app's Settings page always can.
      await openAppSettings();
      return check();
    }

    // Via permission_handler, which asks for ACCESS_BACKGROUND_LOCATION ALONE —
    // the only shape Android 11+ accepts. There it shows no dialog: it opens the
    // app's Location-permission page, and the future completes only when the
    // employee comes back. So do NOT await it (the resume check reports the
    // result); wait just long enough to tell whether anything opened at all.
    final done = Completer<void>();
    unawaited(
      ph.Permission.locationAlways
          .request()
          .then<void>((_) {}, onError: (Object _) {})
          .whenComplete(() {
        if (!done.isCompleted) done.complete();
      }),
    );
    final returnedAtOnce = await done.future
        .then((_) => true)
        .timeout(const Duration(milliseconds: 800), onTimeout: () => false);

    if (returnedAtOnce && await Geolocator.checkPermission() == LocationPermission.whileInUse) {
      // Came straight back with nothing changed: Android showed nothing (it
      // stops routing to the page after repeated refusals). App info works.
      await openAppSettings();
    }
    return check();
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
  /// NEVER COMPLETES.
  ///
  /// Two defences, because either alone is not enough:
  ///  1. After a refusal, ask permission_handler whether Android will ask again
  ///     (`shouldShowRequestPermissionRationale`, which geolocator cannot report).
  ///     If it will not, remember `deniedForever` so the employee gets the
  ///     Settings instructions instead of a button that cannot work.
  ///  2. TIME OUT the request. A future that never completes must never be able
  ///     to wedge the screen, whatever a future plugin version does.
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

    // We asked and were refused. CAN WE ASK AGAIN? This can only be answered
    // HERE — after a request. `shouldShowRequestPermissionRationale` is false
    // both when a permission is permanently denied AND when it has never been
    // asked for, so consulting it BEFORE asking cannot tell those apart. After
    // asking, false means Android will not show the dialog again.
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
