import 'dart:async';
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
  /// One entry per check, true when that check was allowed to raise a dialog.
  /// The mount and the retry buttons may; a resume never may.
  final asks = <bool>[];
  int openedLocation = 0;
  int openedApp = 0;
  ScriptedGate(this.script);

  @override
  Future<GateVerdict> check({bool interactive = false}) async {
    asks.add(interactive);
    return script[(checks++).clamp(0, script.length - 1)];
  }

  @override
  Future<void> openAppSettings() async => openedApp++;

  @override
  Future<void> openLocationSettings() async => openedLocation++;
}

/// A gate whose first check never completes until [release] is called — the
/// shape of the geolocator bug where an empty grantResults array leaves the
/// permission future hanging forever.
class HangingGate implements LocationGateService {
  int starts = 0;
  final _first = Completer<GateVerdict>();

  void release() => _first.complete(GateVerdict.permissionDenied);

  @override
  Future<GateVerdict> check({bool interactive = false}) {
    starts += 1;
    return starts == 1 ? _first.future : Future.value(GateVerdict.permissionDenied);
  }

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<void> openLocationSettings() async {}
}

Future<Widget> harness(LocationGateService gate) async {
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

  testWidgets('the MOUNT may prompt; a resume never does (no Settings loop)', (tester) async {
    // The regression test for the loop this design exists to avoid: returning
    // from Settings IS a resume, so if the resume check could prompt, the user
    // would be thrown straight back out to Settings forever.
    final gate = ScriptedGate([GateVerdict.ok, GateVerdict.backgroundDenied]);
    await tester.pumpWidget(await harness(gate));
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(gate.asks, [true, false]);
  });

  testWidgets('foreground-only blocks with the "Allow all the time" instruction', (tester) async {
    final gate = ScriptedGate([GateVerdict.backgroundDenied, GateVerdict.ok]);
    await tester.pumpWidget(await harness(gate));
    await tester.pumpAndSettle();

    expect(find.text('THE APP'), findsNothing);
    expect(find.text('Set location to "Allow all the time"'), findsOneWidget);
    // It names BOTH switches, so one trip to Settings is enough.
    expect(find.textContaining('Use precise location'), findsOneWidget);

    await tester.tap(find.text('Open app settings'));
    expect(gate.openedApp, 1);

    // Coming back with Always granted clears it.
    await tester.tap(find.text('Check again'));
    await tester.pumpAndSettle();
    expect(find.text('THE APP'), findsOneWidget);
  });

  testWidgets('a check that never returns cannot freeze the retry button', (tester) async {
    // The regression test for the frozen screen seen on a device 2026-09-14:
    // Android declines to show the dialog once a permission is permanently
    // denied and hands back an EMPTY grantResults, whereupon geolocator returns
    // without calling its callback and the future never completes. The gate's
    // re-entrancy guard then stayed raised and every later tap did nothing.
    final gate = HangingGate();
    await tester.pumpWidget(await harness(gate));
    await tester.pump();

    // First check is in flight and will never finish.
    expect(gate.starts, 1);
    gate.release();
    await tester.pumpAndSettle();

    // The screen is usable again: a tap gets through rather than being swallowed.
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(gate.starts, greaterThan(1), reason: 'the retry was swallowed by a stuck guard');
  });

  testWidgets('a resume must not downgrade deniedForever back to a dead Try again', (tester) async {
    // The bug seen on a device 2026-09-14, in gate terms. The interactive check
    // discovers deniedForever (only a REQUEST can learn that — geolocator's
    // checkPermission never returns it), then a resume fires immediately and a
    // passive check reports plain `denied`, overwriting the correct screen. The
    // employee is put back on a "Try again" that Android will never honour.
    //
    // The real GeolocatorGateService remembers the fact; this pins the SCREEN
    // behaviour that guarantees.
    final gate = ScriptedGate([GateVerdict.permissionDeniedForever, GateVerdict.permissionDeniedForever]);
    await tester.pumpWidget(await harness(gate));
    await tester.pumpAndSettle();
    expect(find.text('Location access is blocked'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    // Still the screen with the button that actually works.
    expect(find.text('Location access is blocked'), findsOneWidget);
    expect(find.text('Open app settings'), findsOneWidget);
    expect(find.text('Allow location access'), findsNothing);
  });

  testWidgets('a deliberate retry IS allowed to prompt', (tester) async {
    final gate = ScriptedGate([GateVerdict.permissionDenied, GateVerdict.ok]);
    await tester.pumpWidget(await harness(gate));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(gate.asks, [true, true]);
  });
}
