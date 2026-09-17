import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/device/device_readiness_service.dart';
import 'package:hris_mobile/features/tracking/battery_warning_card.dart';
import 'package:hris_mobile/shared/theme.dart';
import 'package:provider/provider.dart';

// The Time Clock's battery warning (2026-09-17): shown only while the phone may
// stop the app in the background, with the exemption one tap away, and gone
// once the phone says it is exempt.

class _Device implements DeviceReadinessService {
  bool unrestricted;
  int requests = 0;
  _Device(this.unrestricted);

  @override
  Future<DeviceReadiness> check() async => DeviceReadiness(notificationsGranted: true, batteryUnrestricted: unrestricted);
  @override
  Future<void> requestNotifications() async {}
  @override
  Future<void> requestBatteryExemption() async {
    requests += 1;
    unrestricted = true; // the user allowed it in the system dialog
  }
  @override
  Future<void> openAppSettings() async {}
  @override
  Future<Set<String>> skippedSteps() async => {};
  @override
  Future<void> skipStep(String name) async {}
}

Widget _host(DeviceReadinessService? device) {
  final card = const Scaffold(body: BatteryWarningCard());
  final app = MaterialApp(theme: buildTheme(), home: card);
  return device == null ? app : Provider<DeviceReadinessService>.value(value: device, child: app);
}

void main() {
  testWidgets('warns while battery optimisation is on, and the button asks for the exemption', (tester) async {
    final device = _Device(false);
    await tester.pumpWidget(_host(device));
    await tester.pumpAndSettle();
    expect(find.textContaining('Battery saving may stop'), findsOneWidget);

    await tester.tap(find.text('Allow in the background'));
    await tester.pumpAndSettle();
    expect(device.requests, 1);
    // Re-checked after the request: the phone is exempt now, so the card is gone.
    expect(find.textContaining('Battery saving may stop'), findsNothing);
  });

  testWidgets('shows nothing when the phone is already exempt', (tester) async {
    await tester.pumpWidget(_host(_Device(true)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Battery saving may stop'), findsNothing);
  });

  testWidgets('shows nothing when no readiness service is provided', (tester) async {
    await tester.pumpWidget(_host(null));
    await tester.pumpAndSettle();
    expect(find.byType(BatteryWarningCard), findsOneWidget);
    expect(find.textContaining('Battery saving may stop'), findsNothing);
  });
}
