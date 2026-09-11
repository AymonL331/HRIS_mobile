import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// One GPS reading, taken fresh for one purpose (a punch or a range check).
class LocationFix {
  final double latitude;
  final double longitude;
  final double accuracyM;
  final bool isMocked;
  final DateTime at;

  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyM,
    required this.isMocked,
    required this.at,
  });

  Map<String, dynamic> toJson() => {'latitude': latitude, 'longitude': longitude, 'accuracy': accuracyM};
}

/// What the app decides about a fix BEFORE anything is sent.
sealed class FixValidation {
  const FixValidation();
}

class FixOk extends FixValidation {
  /// Worse than the server's flag threshold: the punch goes through but will
  /// be flagged `low_accuracy` for HR — the user is told so.
  final bool warnLowAccuracy;
  const FixOk({required this.warnLowAccuracy});
}

class FixMocked extends FixValidation {
  const FixMocked();
}

class FixTooCoarse extends FixValidation {
  final double accuracyM;
  const FixTooCoarse(this.accuracyM);
}

/// Mirrors the server's `LOCATION_ACCURACY_THRESHOLD_M` (100 m, flag only) and
/// adds the app's own hard floor: a fix worse than 500 m is not evidence of
/// anything and is refused on the phone. A mocked position is always refused.
FixValidation validateFix(LocationFix fix, {double warnAboveM = 100, double rejectAboveM = 500}) {
  if (fix.isMocked) return const FixMocked();
  if (fix.accuracyM > rejectAboveM) return FixTooCoarse(fix.accuracyM);
  return FixOk(warnLowAccuracy: fix.accuracyM > warnAboveM);
}

class FixTimeout implements Exception {
  const FixTimeout();
}

abstract class LocationFixService {
  /// A FRESH high-accuracy reading, never a cached one. Throws [FixTimeout]
  /// when the device cannot produce one within the limit.
  Future<LocationFix> acquire();
}

class GeolocatorFixService implements LocationFixService {
  /// Debug-only switch (Settings › Developer): the emulator's `geo fix` reports
  /// `isMocked = false`, so this is how the refusal path is exercised there.
  static bool simulateMocked = false;

  const GeolocatorFixService();

  @override
  Future<LocationFix> acquire() async {
    Position p;
    try {
      p = await Geolocator.getCurrentPosition(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 15),
        ),
      );
    } on TimeoutException {
      throw const FixTimeout();
    }
    return LocationFix(
      latitude: p.latitude,
      longitude: p.longitude,
      accuracyM: p.accuracy,
      isMocked: p.isMocked || simulateMocked,
      at: DateTime.now(),
    );
  }
}
