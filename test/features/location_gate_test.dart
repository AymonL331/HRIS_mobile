import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/auth/session_controller.dart';
import 'package:hris_mobile/core/auth/session_store.dart';
import 'package:hris_mobile/core/config/env_store.dart';
import 'package:hris_mobile/core/device/device_readiness_service.dart';
import 'package:hris_mobile/core/location/location_gate_service.dart';
import 'package:hris_mobile/features/shell/location_gate.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A gate whose answer is whatever [current] is. A test plays the employee by
/// setting what the dialog / Settings page "results in" before tapping.
class ScriptedGate implements LocationGateService {
  GateVerdict current;
  GateVerdict? afterForeground;
  GateVerdict? afterBackground;
  int checks = 0;
  int foreground = 0;
  int background = 0;
  int openedLocation = 0;
  int openedApp = 0;

  ScriptedGate(this.current);

  @override
  Future<GateVerdict> check() async {
    checks++;
    return current;
  }

  @override
  Future<GateVerdict> requestForeground() async {
    foreground++;
    if (afterForeground != null) current = afterForeground!;
    return current;
  }

  @override
  Future<GateVerdict> requestBackground() async {
    background++;
    if (afterBackground != null) current = afterBackground!;
    return current;
  }

  @override
  Future<void> openAppSettings() async => openedApp++;

  @override
  Future<void> openLocationSettings() async => openedLocation++;
}

/// A gate whose first check never completes until [release] — the shape of the
/// geolocator bug where an empty grantResults array leaves a future hanging.
class HangingGate implements LocationGateService {
  int starts = 0;
  final _first = Completer<GateVerdict>();

  void release() => _first.complete(GateVerdict.permissionDenied);

  @override
  Future<GateVerdict> check() {
    starts += 1;
    return starts == 1 ? _first.future : Future.value(GateVerdict.permissionDenied);
  }

  @override
  Future<GateVerdict> requestForeground() async => GateVerdict.permissionDenied;

  @override
  Future<GateVerdict> requestBackground() async => GateVerdict.permissionDenied;

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<void> openLocationSettings() async {}
}

class ScriptedDevice implements DeviceReadinessService {
  bool notifications;
  bool battery;
  String manufacturer;
  final Set<String> skipped;
  int notificationRequests = 0;
  int batteryRequests = 0;
  int openedApp = 0;

  ScriptedDevice({this.notifications = true, this.battery = true, this.manufacturer = '', Set<String>? skipped})
      : skipped = skipped ?? {};

  @override
  Future<DeviceReadiness> check() async =>
      DeviceReadiness(notificationsGranted: notifications, batteryUnrestricted: battery, manufacturer: manufacturer);

  @override
  Future<void> requestNotifications() async {
    notificationRequests++;
    notifications = true; // the employee tapped Allow
  }

  @override
  Future<void> requestBatteryExemption() async => batteryRequests++;


  @override
  Future<void> openAppSettings() async => openedApp++;

  @override
  Future<Set<String>> skippedSteps() async => {...skipped};

  @override
  Future<void> skipStep(String name) async => skipped.add(name);
}

Future<Widget> harness(LocationGateService gate, [DeviceReadinessService? device]) async {
  SharedPreferences.setMockInitialValues({});
  final env = EnvStore();
  await env.load();
  final session = SessionController(env: env, store: InMemorySessionStore(), appVersion: '1');
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<EnvStore>.value(value: env),
      ChangeNotifierProvider<SessionController>.value(value: session),
      Provider<LocationGateService>.value(value: gate),
      Provider<DeviceReadinessService>.value(value: device ?? ScriptedDevice()),
    ],
    child: const MaterialApp(home: LocationGate(child: Scaffold(body: Text('THE APP')))),
  );
}

/// The wizard scrolls on a test-sized screen; bring the button into view first.
Future<void> tapText(WidgetTester tester, String text) async {
  final f = find.text(text);
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> resume(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a fresh install EXPLAINS FIRST: arriving raises no dialog (user, 2026-09-14)', (tester) async {
    // The complaint this wizard answers: Android's dialog used to appear the
    // moment the employee signed in, with nothing telling them what to pick.
    final gate = ScriptedGate(GateVerdict.permissionDenied);
    await tester.pumpWidget(await harness(gate));
    await tester.pumpAndSettle();

    expect(find.text('THE APP'), findsNothing);
    expect(find.text('Allow location access'), findsOneWidget);
    expect(find.text('PHONE SETUP · STEP 2 OF 5'), findsOneWidget);
    // The drawing of the dialog, with the right choice named.
    expect(find.text('While using the app'), findsOneWidget);
    expect(gate.foreground, 0, reason: 'no dialog before the explanation');
    expect(gate.background, 0);
  });

  testWidgets('the drawing marks "Only this time" as a right tap too; only "Don\'t allow" is struck out', (tester) async {
    await tester.pumpWidget(await harness(ScriptedGate(GateVerdict.permissionDenied)));
    await tester.pumpAndSettle();

    TextDecoration? decorationOf(String label) => tester.widget<Text>(find.text(label)).style?.decoration;
    expect(decorationOf('While using the app'), isNot(TextDecoration.lineThrough));
    expect(decorationOf('Only this time'), isNot(TextDecoration.lineThrough));
    expect(decorationOf('Don’t allow'), TextDecoration.lineThrough);
    expect(find.text('Tap'), findsNWidgets(2), reason: 'both acceptable choices carry the Tap pill');
  });

  testWidgets('"Only this time" moves on exactly like "While using the app"', (tester) async {
    // Android reports a one-time grant as while-in-use, so the gate lands on the
    // "Allow all the time" step — the step that replaces it in Settings.
    final gate = ScriptedGate(GateVerdict.permissionDenied)..afterForeground = GateVerdict.backgroundDenied;
    await tester.pumpWidget(await harness(gate));
    await tester.pumpAndSettle();
    await tapText(tester, 'Continue');
    expect(find.text('Set location to "Allow all the time"'), findsOneWidget);
    expect(find.textContaining('You tapped'), findsNothing);
  });

  testWidgets('Continue raises the dialog; "While using the app" moves on to Allow all the time', (tester) async {
    final gate = ScriptedGate(GateVerdict.permissionDenied)..afterForeground = GateVerdict.backgroundDenied;
    await tester.pumpWidget(await harness(gate));
    await tester.pumpAndSettle();

    await tapText(tester, 'Continue');
    expect(gate.foreground, 1);
    expect(find.text('Set location to "Allow all the time"'), findsOneWidget);
    expect(find.text('PHONE SETUP · STEP 3 OF 5'), findsOneWidget);
    // Settings is NOT opened by itself — that is the next button.
    expect(gate.background, 0);
  });

  testWidgets('answering "Don\'t allow" stays on the step and says what went wrong', (tester) async {
    final gate = ScriptedGate(GateVerdict.permissionDenied)..afterForeground = GateVerdict.permissionDenied;
    await tester.pumpWidget(await harness(gate));
    await tester.pumpAndSettle();
    expect(find.textContaining('You tapped'), findsNothing);

    await tapText(tester, 'Continue');
    expect(find.text('Allow location access'), findsOneWidget);
    expect(find.textContaining('You tapped'), findsOneWidget);
  });

  testWidgets('Open settings goes for "all the time"; coming back with it granted opens the app', (tester) async {
    final gate = ScriptedGate(GateVerdict.backgroundDenied);
    await tester.pumpWidget(await harness(gate));
    await tester.pumpAndSettle();

    // Both switches are named, so one trip to Settings is enough.
    expect(find.text('Use precise location'), findsOneWidget);
    await tapText(tester, 'Open settings');
    expect(gate.background, 1);
    expect(find.text('THE APP'), findsNothing);

    // The employee picks Allow all the time and presses Back.
    gate.current = GateVerdict.ok;
    await resume(tester);
    expect(find.text('THE APP'), findsOneWidget);
  });

  testWidgets('a resume only observes — it never prompts (no Settings loop)', (tester) async {
    // Returning from Settings IS a resume, so a prompting resume would throw the
    // employee straight back out to Settings forever.
    final gate = ScriptedGate(GateVerdict.backgroundDenied);
    await tester.pumpWidget(await harness(gate));
    await tester.pumpAndSettle();
    await resume(tester);
    await resume(tester);

    expect(gate.checks, 3);
    expect(gate.foreground, 0);
    expect(gate.background, 0);
  });

  testWidgets('blocked for good gives the App-info path, never a dead retry', (tester) async {
    final gate = ScriptedGate(GateVerdict.permissionDeniedForever);
    await tester.pumpWidget(await harness(gate));
    await tester.pumpAndSettle();

    expect(find.text('Location access is blocked'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
    await tapText(tester, 'Open app settings');
    expect(gate.background, 1, reason: 'the service routes a blocked grant to App info');

    // A resume must not downgrade it back to a button Android will never honour.
    await resume(tester);
    expect(find.text('Location access is blocked'), findsOneWidget);
  });

  testWidgets('Approximate asks only for the precise switch', (tester) async {
    final gate = ScriptedGate(GateVerdict.reducedAccuracy);
    await tester.pumpWidget(await harness(gate));
    await tester.pumpAndSettle();
    expect(find.text('Precise location is required'), findsOneWidget);
    await tapText(tester, 'Open settings');
    expect(gate.background, 1);
  });

  testWidgets('location off offers the location settings and clears on Check again', (tester) async {
    final gate = ScriptedGate(GateVerdict.serviceOff);
    await tester.pumpWidget(await harness(gate));
    await tester.pumpAndSettle();

    expect(find.text('Turn on location'), findsOneWidget);
    await tapText(tester, 'Open location settings');
    expect(gate.openedLocation, 1);

    gate.current = GateVerdict.ok;
    await tapText(tester, 'Check again');
    expect(find.text('THE APP'), findsOneWidget);
  });

  testWidgets('location steps cannot be skipped', (tester) async {
    for (final v in [GateVerdict.serviceOff, GateVerdict.permissionDenied, GateVerdict.backgroundDenied]) {
      await tester.pumpWidget(await harness(ScriptedGate(v)));
      await tester.pumpAndSettle();
      expect(find.text('Skip for now'), findsNothing, reason: '$v');
    }
  });

  testWidgets('with location done, notifications then battery are asked, and battery can be skipped', (tester) async {
    final device = ScriptedDevice(notifications: false, battery: false);
    await tester.pumpWidget(await harness(ScriptedGate(GateVerdict.ok), device));
    await tester.pumpAndSettle();

    expect(find.text('Allow notifications'), findsOneWidget);
    await tapText(tester, 'Continue');
    expect(device.notificationRequests, 1);

    expect(find.text('Let HRIS run in the background'), findsOneWidget);
    expect(find.text('PHONE SETUP · STEP 5 OF 5'), findsOneWidget);
    await tapText(tester, 'Continue');
    expect(device.batteryRequests, 1);
    // Still unrestricted = false (some ROMs never grant it): the way past is a
    // deliberate skip, which is remembered.
    await tapText(tester, 'Skip for now');
    expect(device.skipped, contains('battery'));
    expect(find.text('THE APP'), findsOneWidget);
  });

  testWidgets('a step skipped earlier is not asked again', (tester) async {
    final device = ScriptedDevice(battery: false, skipped: {'battery'});
    await tester.pumpWidget(await harness(ScriptedGate(GateVerdict.ok), device));
    await tester.pumpAndSettle();
    expect(find.text('THE APP'), findsOneWidget);
  });

  testWidgets('a Xiaomi phone gets the brand-specific hint and an App settings button', (tester) async {
    final device = ScriptedDevice(battery: false, manufacturer: 'xiaomi');
    await tester.pumpWidget(await harness(ScriptedGate(GateVerdict.ok), device));
    await tester.pumpAndSettle();

    expect(find.textContaining('Xiaomi'), findsOneWidget);
    expect(find.textContaining('Autostart'), findsOneWidget);
    await tapText(tester, 'Open app settings');
    expect(device.openedApp, 1);
  });

  testWidgets('Back re-shows the previous step to re-read; nothing is requested; Next returns', (tester) async {
    final gate = ScriptedGate(GateVerdict.backgroundDenied);
    await tester.pumpWidget(await harness(gate));
    await tester.pumpAndSettle();
    expect(find.text('Set location to "Allow all the time"'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Allow location access'), findsOneWidget);
    expect(find.text('PHONE SETUP · STEP 2 OF 5'), findsOneWidget);
    expect(find.textContaining('already done this step'), findsOneWidget);
    expect(find.text('Continue'), findsNothing, reason: 'a completed step offers Next, not its dialog');

    // Back again reaches step 1; there is no step before it.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Turn on location'), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);

    await tapText(tester, 'Next');
    await tapText(tester, 'Next');
    expect(find.text('Set location to "Allow all the time"'), findsOneWidget);
    expect(find.textContaining('already done this step'), findsNothing);
    expect(gate.foreground, 0);
    expect(gate.background, 0);
    expect(gate.openedLocation, 0);
  });

  testWidgets('the phone back gesture follows the back arrow instead of leaving the app', (tester) async {
    await tester.pumpWidget(await harness(ScriptedGate(GateVerdict.backgroundDenied)));
    await tester.pumpAndSettle();

    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(find.text('Allow location access'), findsOneWidget);
  });

  testWidgets('the first step has no back arrow', (tester) async {
    await tester.pumpWidget(await harness(ScriptedGate(GateVerdict.serviceOff)));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back'), findsNothing);
  });

  testWidgets('real progress while re-reading ends the review', (tester) async {
    final gate = ScriptedGate(GateVerdict.backgroundDenied);
    await tester.pumpWidget(await harness(gate));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Allow location access'), findsOneWidget);

    // Meanwhile "Allow all the time" was granted in Settings.
    gate.current = GateVerdict.ok;
    await resume(tester);
    expect(find.text('THE APP'), findsOneWidget);
  });

  testWidgets('every step lays out at phone width with a large system font', (tester) async {
    // Instructions nobody can read are no instructions. ~400 dp wide, 1.5x text.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.7;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    final cases = <(GateVerdict, ScriptedDevice)>[
      (GateVerdict.serviceOff, ScriptedDevice()),
      (GateVerdict.permissionDenied, ScriptedDevice()),
      (GateVerdict.backgroundDenied, ScriptedDevice()),
      (GateVerdict.reducedAccuracy, ScriptedDevice()),
      (GateVerdict.permissionDeniedForever, ScriptedDevice()),
      (GateVerdict.ok, ScriptedDevice(notifications: false)),
      (GateVerdict.ok, ScriptedDevice(battery: false, manufacturer: 'samsung')),
    ];
    for (final (verdict, device) in cases) {
      await tester.pumpWidget(await harness(ScriptedGate(verdict), device));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$verdict ${device.manufacturer}');
      expect(find.text('THE APP'), findsNothing);
    }
  });

  testWidgets('a refresh asked for while a check hangs is queued, not swallowed', (tester) async {
    final gate = HangingGate();
    await tester.pumpWidget(await harness(gate));
    await tester.pump();
    expect(gate.starts, 1);

    // The employee comes back from Settings while the first check is stuck.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    gate.release();
    await tester.pumpAndSettle();
    expect(gate.starts, 2, reason: 'the queued refresh ran after the stuck one finished');
    expect(find.text('Allow location access'), findsOneWidget);
  });
}
