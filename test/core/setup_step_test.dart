import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/device/device_readiness_service.dart';
import 'package:hris_mobile/core/location/location_gate_service.dart';
import 'package:hris_mobile/features/setup/setup_step.dart';

void main() {
  SetupStep? next(GateVerdict v, {bool notif = true, bool battery = true, Set<String> skipped = const {}}) =>
      nextSetupStep(
        location: v,
        device: DeviceReadiness(notificationsGranted: notif, batteryUnrestricted: battery),
        skipped: skipped,
      );

  test('every blocking location verdict maps to one location step', () {
    expect(next(GateVerdict.serviceOff), SetupStep.locationService);
    expect(next(GateVerdict.permissionDenied), SetupStep.locationPermission);
    expect(next(GateVerdict.backgroundDenied), SetupStep.allowAllTheTime);
    expect(next(GateVerdict.reducedAccuracy), SetupStep.allowAllTheTime);
    expect(next(GateVerdict.permissionDeniedForever), SetupStep.allowAllTheTime);
  });

  test('location comes first, whatever else is missing', () {
    for (final v in GateVerdict.values.where((v) => v.blocks)) {
      final s = next(v, notif: false, battery: false);
      expect(s!.skippable, isFalse, reason: '$v');
    }
  });

  test('with location ok: notifications, then battery, then done', () {
    expect(next(GateVerdict.ok, notif: false, battery: false), SetupStep.notifications);
    expect(next(GateVerdict.ok, battery: false), SetupStep.battery);
    expect(next(GateVerdict.ok), isNull);
  });

  test('a skipped optional step is not asked again; location cannot be skipped', () {
    expect(next(GateVerdict.ok, notif: false, skipped: {'notifications'}), isNull);
    expect(next(GateVerdict.ok, notif: false, battery: false, skipped: {'notifications'}), SetupStep.battery);
    expect(next(GateVerdict.ok, battery: false, skipped: {'battery'}), isNull);
    // Skipping names for location steps are ignored.
    expect(next(GateVerdict.backgroundDenied, skipped: {'allowAllTheTime', 'locationPermission'}), SetupStep.allowAllTheTime);
  });

  test('step numbering is 1-based over five steps', () {
    expect(SetupStep.total, 5);
    expect(SetupStep.locationService.number, 1);
    expect(SetupStep.battery.number, 5);
    expect(SetupStep.values.where((s) => s.skippable), [SetupStep.notifications, SetupStep.battery]);
  });

  test('brand hints match loosely and stay silent for stock Android', () {
    expect(oemBatteryHint('Xiaomi')!.brand, contains('Xiaomi'));
    expect(oemBatteryHint('OPPO')!.brand, contains('OPPO'));
    expect(oemBatteryHint('realme')!.brand, contains('realme'));
    expect(oemBatteryHint('vivo'), isNotNull);
    expect(oemBatteryHint('samsung')!.brand, 'Samsung');
    expect(oemBatteryHint('INFINIX MOBILITY LIMITED'), isNotNull);
    expect(oemBatteryHint('Google'), isNull);
    expect(oemBatteryHint(''), isNull);
  });
}
