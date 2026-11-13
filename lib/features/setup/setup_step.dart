import '../../core/device/device_readiness_service.dart';
import '../../core/location/location_gate_service.dart';

// The brand-specific background hints live in core/device — the Time Clock card
// and the Settings row need them too. Re-exported so every existing import of
// this file still sees OemHint / oemBatteryHint.
export '../../core/device/oem_hints.dart';

/// The phone-setup wizard's steps, in the order an employee meets them.
///
/// The ORDER is the point. Android's own dialogs give no instructions, and on
/// Android 11+ asking for "all the time" sends people straight to Settings with
/// no explanation — so every step is explained on our screen FIRST, and the
/// system dialog or Settings page only appears when the employee taps the
/// button under that explanation.
enum SetupStep {
  locationService,
  locationPermission,
  allowAllTheTime,
  notifications,
  battery;

  int get number => index + 1;

  static int get total => values.length;

  /// Nothing is skippable since 2026-11-13 (user: shifts showed hours with no
  /// location because phones closed ATLAS). Notifications carry the "fix this"
  /// alerts and the recording notice; the battery exemption is what keeps the
  /// phone from closing ATLAS in the background. A "Skip for now" chosen on an
  /// older version is ignored.
  bool get skippable => false;
}

/// The one decision, pure so it reads (and tests) as a truth table: which step
/// the employee must see now, or null when the phone is fully set up.
///
/// Every not-`ok` location verdict maps to exactly one step. The three
/// "go to Settings" verdicts share a step because they share the remedy — the
/// app's Location permission page — and differ only in which switch to flip.
SetupStep? nextSetupStep({
  required GateVerdict location,
  required DeviceReadiness device,
  required Set<String> skipped,
}) {
  switch (location) {
    case GateVerdict.serviceOff:
      return SetupStep.locationService;
    case GateVerdict.permissionDenied:
      return SetupStep.locationPermission;
    case GateVerdict.backgroundDenied:
    case GateVerdict.reducedAccuracy:
    case GateVerdict.permissionDeniedForever:
      return SetupStep.allowAllTheTime;
    case GateVerdict.ok:
      break;
  }
  if (!device.notificationsGranted) return SetupStep.notifications;
  if (!device.batteryUnrestricted) return SetupStep.battery;
  return null;
}
