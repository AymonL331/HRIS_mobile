import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/auth/session_controller.dart';
import 'package:hris_mobile/core/auth/session_store.dart';
import 'package:hris_mobile/core/config/env_store.dart';
import 'package:hris_mobile/features/time_clock/time_clock_controller.dart';
import 'package:hris_mobile/features/time_clock/time_clock_screen.dart';
import 'package:hris_mobile/features/tracking/tracking_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/clock_fakes.dart';

void main() {
  group('controller drives the service from the server', () {
    test('every status load syncs the tracking block — start while the shift is open', () async {
      final api = FakeClockApi()..status_ = statusJson(today: clockedIn(), tracking: trackingJson(attendanceLogId: 5));
      final tracking = FakeTrackingService();
      final c = TimeClockController(api: api, fixes: FakeFixService(), tracking: tracking);
      await c.load();
      expect(tracking.synced.single.active, isTrue);
      expect(tracking.synced.single.attendanceLogId, 5);
    });

    test('after a clock-out the next load syncs an INACTIVE state (the service stops)', () async {
      final api = FakeClockApi()..status_ = statusJson(today: clockedIn(), tracking: trackingJson());
      final tracking = FakeTrackingService();
      final c = TimeClockController(api: api, fixes: FakeFixService(), tracking: tracking);
      await c.load();
      api.status_ = statusJson(tracking: trackingJson(active: false, attendanceLogId: null));
      await c.load(silent: true);
      expect(tracking.synced.map((s) => s.active), [true, false]);
    });

    test('a punch reloads the status, so a clock-in syncs straight away', () async {
      final api = FakeClockApi();
      final tracking = FakeTrackingService();
      final c = TimeClockController(api: api, fixes: FakeFixService(), tracking: tracking);
      await c.load();
      await c.punch('in', capture: FakeFaceCapturer().call);
      // load + the reload after the punch.
      expect(tracking.synced.length, 2);
    });
  });

  group('the status card', () {
    Future<(TimeClockController, FakeClockApi)> mount(WidgetTester tester, FakeTrackingService tracking, {bool active = true}) async {
      SharedPreferences.setMockInitialValues({});
      final env = EnvStore();
      await env.load();
      final session = SessionController(env: env, store: InMemorySessionStore(), appVersion: '1');
      final api = FakeClockApi()
        ..status_ = statusJson(today: clockedIn(), tracking: active ? trackingJson(attendanceLogId: 1) : null);
      final c = TimeClockController(api: api, fixes: FakeFixService(), tracking: tracking);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<SessionController>.value(value: session),
          ChangeNotifierProvider<TimeClockController>.value(value: c),
        ],
        child: MaterialApp(home: Scaffold(body: TimeClockScreen(captureOverride: FakeFaceCapturer().call))),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      return (c, api);
    }

    testWidgets('recording: says so, with the queue, and that it stops at clock-out', (tester) async {
      final tracking = FakeTrackingService()
        ..notifier.value = TrackingSnapshot(running: true, attendanceLogId: 1, lastPointAt: DateTime.now().toUtc(), queued: 3);
      await mount(tester, tracking);
      expect(find.text('Recording your work location'), findsOneWidget);
      expect(find.textContaining('3 waiting to upload'), findsOneWidget);
      expect(find.textContaining('stops when you clock out'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('shift open but not recording: says so and Restart re-syncs', (tester) async {
      final tracking = FakeTrackingService()..notifier.value = const TrackingSnapshot(running: false, stopReason: 'could_not_start');
      final (_, api) = await mount(tester, tracking);
      expect(find.text('Location recording is not running'), findsOneWidget);
      expect(find.textContaining('Allow all the time'), findsOneWidget);
      final before = api.statusCalls;
      await tester.ensureVisible(find.text('Restart'));
      await tester.tap(find.text('Restart'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(api.statusCalls, before + 1);
      expect(tracking.synced.length, greaterThanOrEqualTo(2));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('upload failing: the points are said to be safe on the phone', (tester) async {
      final tracking = FakeTrackingService()
        ..notifier.value = const TrackingSnapshot(running: true, attendanceLogId: 1, uploadFailing: true, queued: 40);
      await mount(tester, tracking);
      expect(find.textContaining('saved on this phone'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('no open shift: no card at all', (tester) async {
      await mount(tester, FakeTrackingService(), active: false);
      expect(find.text('Recording your work location'), findsNothing);
      expect(find.text('Location recording is not running'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
