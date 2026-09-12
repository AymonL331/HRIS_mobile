import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/auth/session_controller.dart';
import 'package:hris_mobile/core/auth/session_store.dart';
import 'package:hris_mobile/core/config/env_store.dart';
import 'package:hris_mobile/core/http/api_exception.dart';
import 'package:hris_mobile/core/location/location_fix.dart';
import 'package:hris_mobile/features/time_clock/time_clock_controller.dart';
import 'package:hris_mobile/features/time_clock/time_clock_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/clock_fakes.dart';

Future<TimeClockController> mount(WidgetTester tester, FakeClockApi api, FakeFixService fixes, {FakeFaceCapturer? face}) async {
  SharedPreferences.setMockInitialValues({});
  final env = EnvStore();
  await env.load();
  final session = SessionController(env: env, store: InMemorySessionStore(), appVersion: '1');
  final controller = TimeClockController(api: api, fixes: fixes);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<SessionController>.value(value: session),
      ChangeNotifierProvider<TimeClockController>.value(value: controller),
    ],
    // The face check is stubbed: a widget test cannot run a WebView or a
    // camera, and what these tests are about is the punch flow AROUND it.
    child: MaterialApp(home: Scaffold(body: TimeClockScreen(captureOverride: (face ?? FakeFaceCapturer()).call))),
  ));
  // The screen ticks every second, so never pumpAndSettle here.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return controller;
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

FilledButton button(WidgetTester tester, String label) => tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));

void main() {
  testWidgets('shows the employee, the server clock in Manila, and the button rules for a fresh day', (tester) async {
    await mount(tester, FakeClockApi(), FakeFixService());
    expect(find.text('Sofia Sandbox'), findsOneWidget);
    expect(find.text('EMP01670'), findsOneWidget);
    expect(find.text('Server time (Manila)'), findsOneWidget);
    expect(find.textContaining('Allowed radius 200 m around Head Office'), findsOneWidget);
    expect(button(tester, 'Time In').onPressed, isNotNull);
    expect(button(tester, 'Time Out').onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Time In takes a fix, records, shows the success card, flips the buttons', (tester) async {
    final api = FakeClockApi();
    final fixes = FakeFixService();
    await mount(tester, api, fixes);
    await tester.tap(find.widgetWithText(FilledButton, 'Time In'));
    await settle(tester);
    expect(fixes.acquired, 1);
    expect(api.punches.single['direction'], 'in');
    expect(find.text('8:13 AM'), findsOneWidget); // today card, Manila
    expect(find.textContaining('Timed in at 8:13 AM. In range (41 m from the worksite).'), findsOneWidget);
    expect(button(tester, 'Time In').onPressed, isNull);
    expect(button(tester, 'Time Out').onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a mocked fix is refused on the phone and nothing is sent', (tester) async {
    final api = FakeClockApi();
    final fixes = FakeFixService()..next = LocationFix(latitude: 1, longitude: 1, accuracyM: 4, isMocked: true, at: DateTime.now());
    await mount(tester, api, fixes);
    await tester.tap(find.widgetWithText(FilledButton, 'Time In'));
    await settle(tester);
    expect(api.punches, isEmpty);
    expect(find.textContaining('Mock location detected'), findsOneWidget);
    expect(button(tester, 'Time In').onPressed, isNotNull); // still allowed to try again
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a 409 is shown as information and the day is reloaded', (tester) async {
    final api = FakeClockApi()..punchError = const ApiException(status: 409, message: 'Already clocked in for today.');
    await mount(tester, api, FakeFixService());
    await tester.tap(find.widgetWithText(FilledButton, 'Time In'));
    await settle(tester);
    expect(find.text('Already clocked in for today.'), findsOneWidget);
    expect(api.statusCalls, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a geofence block is shown as a blocked card with advice', (tester) async {
    final api = FakeClockApi()
      ..punchError = const ApiException(
        status: 422,
        message: 'You appear to be outside the allowed worksite area — clock blocked.',
        fieldErrors: {'location': 'Outside the allowed worksite radius (~6470 m away).'},
      );
    await mount(tester, api, FakeFixService());
    await tester.tap(find.widgetWithText(FilledButton, 'Time In'));
    await settle(tester);
    expect(find.textContaining('clock blocked. Move closer to your worksite'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no consent on record shows the consent screen first; agreeing unlocks the clock', (tester) async {
    final api = FakeClockApi()..status_ = statusJson(consent: false);
    await mount(tester, api, FakeFixService());
    expect(find.text('Location consent'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Time In'), findsNothing);
    await tester.tap(find.textContaining('I agree'));
    await settle(tester);
    expect(api.consents, 1);
    expect(find.widgetWithText(FilledButton, 'Time In'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a branch with no worksite says so and hides the range check', (tester) async {
    final api = FakeClockApi()..status_ = statusJson(worksite: false);
    await mount(tester, api, FakeFixService());
    expect(find.textContaining('No worksite configured for your branch'), findsOneWidget);
    expect(find.byTooltip('Check my range'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
