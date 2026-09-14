import '../../core/device/device_readiness_service.dart';
import '../../core/location/location_gate_service.dart';

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

  /// Location is mandatory — the app does not run without it. These two make
  /// work-hours tracking reliable but some phones cannot grant them, so the
  /// employee may deliberately skip them (remembered).
  bool get skippable => this == notifications || this == battery;
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
  if (!device.notificationsGranted && !skipped.contains(SetupStep.notifications.name)) {
    return SetupStep.notifications;
  }
  if (!device.batteryUnrestricted && !skipped.contains(SetupStep.battery.name)) {
    return SetupStep.battery;
  }
  return null;
}

/// Extra, brand-specific background settings. These brands stop background
/// apps on top of stock Android's battery optimisation, and no API reports
/// those switches — so the best the app can do is name them.
class OemHint {
  final String brand;
  final List<String> steps;

  const OemHint(this.brand, this.steps);
}

/// The hint for a `Build.MANUFACTURER`, or null for phones that follow stock
/// Android (Google Pixel, Motorola, Nokia…). Matched loosely: some brands
/// report a long company name ("INFINIX MOBILITY LIMITED").
OemHint? oemBatteryHint(String manufacturer) {
  final m = manufacturer.toLowerCase().trim();
  if (m.isEmpty) return null;
  bool any(List<String> names) => names.any(m.contains);

  if (any(const ['xiaomi', 'redmi', 'poco'])) {
    return const OemHint('Xiaomi / Redmi / POCO', [
      'App settings › Autostart: turn it ON.',
      'App settings › Battery saver: choose "No restrictions".',
    ]);
  }
  if (any(const ['oppo', 'realme', 'oneplus'])) {
    return const OemHint('OPPO / realme / OnePlus', [
      'App settings › Battery usage: turn ON "Allow background activity".',
      'Also turn ON "Allow auto launch" if you see it.',
    ]);
  }
  if (any(const ['vivo', 'iqoo'])) {
    return const OemHint('vivo', [
      'Settings › Battery › Background power consumption: allow HRIS.',
      'Also turn ON Auto-start for HRIS if you see it.',
    ]);
  }
  if (any(const ['samsung'])) {
    return const OemHint('Samsung', [
      'App settings › Battery: choose "Unrestricted".',
      'Settings › Battery › Background usage limits: HRIS must NOT be in "Sleeping apps".',
    ]);
  }
  if (any(const ['huawei', 'honor'])) {
    return const OemHint('HUAWEI / HONOR', [
      'Settings › Battery › App launch › HRIS: turn OFF "Manage automatically".',
      'Then turn ON Auto-launch, Secondary launch and Run in background.',
    ]);
  }
  if (any(const ['infinix', 'tecno', 'itel'])) {
    return const OemHint('Infinix / TECNO / itel', [
      'Phone Master (or Settings › App management) › Auto-start: allow HRIS.',
      'Lock HRIS in the recent-apps screen so it is not cleared.',
    ]);
  }
  return null;
}
