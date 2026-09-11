import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/auth/session_controller.dart';
import 'package:hris_mobile/core/auth/session_store.dart';
import 'package:hris_mobile/core/config/env_store.dart';
import 'package:hris_mobile/core/location/location_gate_service.dart';
import 'package:hris_mobile/features/shell/location_gate.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScriptedGate implements LocationGateService {
  final List<GateVerdict> script;
  int checks = 0;
  int openedLocation = 0;
  int openedApp = 0;
  ScriptedGate(this.script);

  @override
  Future<GateVerdict> check() async => script[(checks++).clamp(0, script.length - 1)];

  @override
  Future<void> openAppSettings() async => openedApp++;

  @override
  Future<void> openLocationSettings() async => openedLocation++;
}

Future<Widget> harness(ScriptedGate gate) async {
  SharedPreferences.setMockInitialValues({});
  final env = EnvStore();
  await env.load();
  final session = SessionController(env: env, store: InMemorySessionStore(), appVersion: '1');
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<EnvStore>.value(value: env),
      ChangeNotifierProvider<SessionController>.value(value: session),
      Provider<LocationGateService>.value(value: gate),
    ],
    child: const MaterialApp(home: LocationGate(child: Scaffold(body: Text('THE APP')))),
  );
}

void main() {
  testWidgets('location off blocks the child, offers the location settings, and clears on retry', (tester) async {
    final gate = ScriptedGate([GateVerdict.serviceOff, GateVerdict.ok]);
    await tester.pumpWidget(await harness(gate));
    await tester.pumpAndSettle();

    expect(find.text('THE APP'), findsNothing);
    expect(find.text('Turn on location'), findsOneWidget);
    await tester.tap(find.text('Open location settings'));
    expect(gate.openedLocation, 1);

    await tester.tap(find.text('Check again'));
    await tester.pumpAndSettle();
    expect(find.text('THE APP'), findsOneWidget);
  });

  testWidgets('Approximate accuracy blocks with the precise hint and the app settings button', (tester) async {
    final gate = ScriptedGate([GateVerdict.reducedAccuracy]);
    await tester.pumpWidget(await harness(gate));
    await tester.pumpAndSettle();
    expect(find.text('Precise location is required'), findsOneWidget);
    await tester.tap(find.text('Open app settings'));
    expect(gate.openedApp, 1);
    expect(find.text('THE APP'), findsNothing);
  });

  testWidgets('denied forever explains the settings path', (tester) async {
    await tester.pumpWidget(await harness(ScriptedGate([GateVerdict.permissionDeniedForever])));
    await tester.pumpAndSettle();
    expect(find.text('Location access is blocked'), findsOneWidget);
    expect(find.text('Open app settings'), findsOneWidget);
  });

  testWidgets('plain denied offers Try again, which re-checks', (tester) async {
    await tester.pumpWidget(await harness(ScriptedGate([GateVerdict.permissionDenied, GateVerdict.ok])));
    await tester.pumpAndSettle();
    expect(find.text('Allow location access'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('THE APP'), findsOneWidget);
  });

  testWidgets('coming back to the foreground re-checks', (tester) async {
    final gate = ScriptedGate([GateVerdict.ok, GateVerdict.serviceOff]);
    await tester.pumpWidget(await harness(gate));
    await tester.pumpAndSettle();
    expect(find.text('THE APP'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(gate.checks, 2);
    expect(find.text('Turn on location'), findsOneWidget);
  });
}
