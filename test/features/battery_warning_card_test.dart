import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/device/device_readiness_service.dart';
import 'package:hris_mobile/features/tracking/background_running_tile.dart';
import 'package:hris_mobile/features/tracking/battery_warning_card.dart';
import 'package:hris_mobile/shared/theme.dart';
import 'package:provider/provider.dart';

// Whether the phone will leave HRIS running during a shift, on the two surfaces
// that ask: the Time Clock WARNS when the answer is no; Settings SHOWS the
// answer at all times (the user has four phones on four Android skins — only one
// of them even has the word "Optimized" — so a state you can only see when it is
// broken is not much use).
//
// The brand steps are the part no API can check, so they are shown from the
// phone's manufacturer whether or not Android says the app is exempt.

class _Device implements DeviceReadinessService {
  bool unrestricted;
  final String manufacturer;
  int requests = 0;
  int settingsOpened = 0;
  _Device(this.unrestricted, {this.manufacturer = ''});

  @override
  Future<DeviceReadiness> check() async => DeviceReadiness(
        notificationsGranted: true,
        batteryUnrestricted: unrestricted,
        manufacturer: manufacturer,
      );
  @override
  Future<void> requestNotifications() async {}
  @override
  Future<void> requestBatteryExemption() async {
    requests += 1;
    unrestricted = true; // the user allowed it in the system dialog
  }

  @override
  Future<void> requestExactAlarms() async {}
  @override
  Future<void> openAppSettings() async {
    settingsOpened += 1;
  }
  @override
  Future<Set<String>> skippedSteps() async => {};
  @override
  Future<void> skipStep(String name) async {}
}

Widget _host(DeviceReadinessService? device, Widget child) {
  final app = MaterialApp(theme: buildTheme(), home: Scaffold(body: SingleChildScrollView(child: child)));
  return device == null ? app : Provider<DeviceReadinessService>.value(value: device, child: app);
}

void main() {
  group('Time Clock warning card', () {
    testWidgets('warns while battery optimisation is on, and the button asks for the exemption', (tester) async {
      final device = _Device(false);
      await tester.pumpWidget(_host(device, const BatteryWarningCard()));
      await tester.pumpAndSettle();
      expect(find.textContaining('Battery saving may stop'), findsOneWidget);

      await tester.tap(find.text('Allow in the background'));
      await tester.pumpAndSettle();
      expect(device.requests, 1);
      // Re-checked after the request: the phone is exempt now, so the card is gone.
      expect(find.textContaining('Battery saving may stop'), findsNothing);
    });

    testWidgets('names the brand steps no dialog can set, and offers app settings', (tester) async {
      final device = _Device(false, manufacturer: 'Xiaomi');
      await tester.pumpWidget(_host(device, const BatteryWarningCard()));
      await tester.pumpAndSettle();
      expect(find.textContaining('On Xiaomi / Redmi / POCO phones'), findsOneWidget);
      expect(find.textContaining('Autostart'), findsOneWidget);

      await tester.tap(find.text('Open app settings'));
      await tester.pumpAndSettle();
      expect(device.settingsOpened, 1);
    });

    testWidgets('no "Open app settings" on brands whose steps are elsewhere in the phone\'s Settings (HONOR)', (tester) async {
      final device = _Device(false, manufacturer: 'HONOR');
      await tester.pumpWidget(_host(device, const BatteryWarningCard()));
      await tester.pumpAndSettle();
      expect(find.textContaining('On HUAWEI / HONOR phones'), findsOneWidget);
      expect(find.textContaining("in your phone's Settings"), findsOneWidget);
      // The button would open the app-info page, which has none of those steps.
      expect(find.text('Open app settings'), findsNothing);
    });

    testWidgets('shows nothing when the phone is already exempt, or when nothing can be asked', (tester) async {
      await tester.pumpWidget(_host(_Device(true), const BatteryWarningCard()));
      await tester.pumpAndSettle();
      expect(find.textContaining('Battery saving may stop'), findsNothing);

      await tester.pumpWidget(_host(null, const BatteryWarningCard()));
      await tester.pumpAndSettle();
      expect(find.byType(BatteryWarningCard), findsOneWidget);
      expect(find.textContaining('Battery saving may stop'), findsNothing);
    });
  });

  group('Settings row', () {
    testWidgets('says Allowed on a phone that is exempt — visible even with nothing wrong', (tester) async {
      await tester.pumpWidget(_host(_Device(true), const BackgroundRunningTile()));
      await tester.pumpAndSettle();
      expect(find.text('Background running'), findsOneWidget);
      expect(find.text('Allowed'), findsOneWidget);
      // Nothing to fix, so no button.
      expect(find.text('Allow in the background'), findsNothing);
    });

    testWidgets('says Not allowed and fixes it in one tap', (tester) async {
      final device = _Device(false);
      await tester.pumpWidget(_host(device, const BackgroundRunningTile()));
      await tester.pumpAndSettle();
      expect(find.text('Not allowed'), findsOneWidget);

      await tester.tap(find.text('Allow in the background'));
      await tester.pumpAndSettle();
      expect(device.requests, 1);
      expect(find.text('Allowed'), findsOneWidget);
    });

    testWidgets('keeps the brand steps even when Android says Allowed (no API reports those switches)', (tester) async {
      await tester.pumpWidget(_host(_Device(true, manufacturer: 'realme'), const BackgroundRunningTile()));
      await tester.pumpAndSettle();
      expect(find.text('Allowed'), findsOneWidget);
      expect(find.textContaining('On OPPO / realme / OnePlus phones'), findsOneWidget);
    });

    testWidgets('renders nothing when no readiness service is provided', (tester) async {
      await tester.pumpWidget(_host(null, const BackgroundRunningTile()));
      await tester.pumpAndSettle();
      expect(find.text('Background running'), findsNothing);
    });
  });
}
