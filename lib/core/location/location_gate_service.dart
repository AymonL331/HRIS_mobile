import 'package:geolocator/geolocator.dart';

/// Why the app is (or is not) allowed to run right now.
enum GateVerdict {
  ok,
  serviceOff,
  permissionDenied,
  permissionDeniedForever,
  reducedAccuracy;

  bool get blocks => this != GateVerdict.ok;
}

/// The one decision, pure so it is testable as a truth table.
///
/// The company rule is "the app does not work without location": the device's
/// location service must be on, the app must hold the permission, and on
/// Android 12+ the user must have chosen PRECISE (an "Approximate" grant is a
/// fix good to a few kilometres — useless against a branch geofence). Below
/// Android 12 the accuracy status reads `unknown` while FINE is granted, which
/// is precise by definition.
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
    case LocationPermission.always:
      break;
  }
  if (accuracy == LocationAccuracyStatus.reduced) return GateVerdict.reducedAccuracy;
  return GateVerdict.ok;
}

/// Gathers the three inputs and opens the two settings pages. Abstract so the
/// gate widget can be tested with a scripted fake.
abstract class LocationGateService {
  /// Checks service, permission (asking once if simply not yet decided) and
  /// accuracy, then returns the verdict.
  Future<GateVerdict> check();

  Future<void> openLocationSettings();

  Future<void> openAppSettings();
}

class GeolocatorGateService implements LocationGateService {
  const GeolocatorGateService();

  @override
  Future<GateVerdict> check() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      // The first (and only automatic) ask. A second "denied" here means the
      // user said no to the dialog; "deniedForever" means they ticked don't ask.
      permission = await Geolocator.requestPermission();
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
  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  @override
  Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }
}
