import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/auth/session_controller.dart';
import 'package:hris_mobile/core/auth/session_store.dart';
import 'package:hris_mobile/core/config/env_store.dart';
import 'package:hris_mobile/core/device/device_readiness_service.dart';
import 'package:hris_mobile/features/reminders/notification_bell.dart';
import 'package:hris_mobile/features/reminders/notifications_controller.dart';
import 'package:hris_mobile/features/reminders/notifications_screen.dart';
import 'package:hris_mobile/features/reminders/reminder_coordinator.dart';
import 'package:hris_mobile/features/reminders/reminder_scheduler.dart';
import 'package:hris_mobile/features/reminders/reminder_store.dart';
import 'package:hris_mobile/features/settings/clock_reminders_tile.dart';
import 'package:hris_mobile/features/time_clock/time_clock_controller.dart';
import 'package:hris_mobile/shared/theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/clock_fakes.dart';
import '../fakes/reminder_fakes.dart';

/// An Android 12 phone whose "Alarms & reminders" switch is off.
class _NoExactAlarms extends AlwaysReadyDevice {
  final String manufacturer;
  _NoExactAlarms(this.manufacturer);

  @override
  Future<DeviceReadiness> check() async => DeviceReadiness(
        notificationsGranted: true,
        batteryUnrestricted: true,
        exactAlarmsGranted: false,
        manufacturer: manufacturer,
      );
}

void main() {
  Future<NotificationsController> pumpBell(WidgetTester tester, FakeNotificationsApi api) async {
    final c = NotificationsController(api: api, pollInterval: Duration.zero, observeLifecycle: false);
    await tester.pumpWidget(
      ChangeNotifierProvider<NotificationsController>.value(
        value: c,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(appBar: AppBar(actions: [Builder(builder: (ctx) => NotificationBell(onOpen: () => NotificationsScreen.open(ctx, c)))])),
        ),
      ),
    );
    await c.load();
    await tester.pump();
    return c;
  }

  testWidgets('the bell shows no badge at zero, the count otherwise, capped at 99+', (tester) async {
    final api = FakeNotificationsApi([]);
    final c = await pumpBell(tester, api);
    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    expect(find.text('0'), findsNothing);

    api.rows = [for (var i = 1; i <= 7; i++) notificationJson(id: i, readAt: null)];
    await c.load();
    await tester.pump();
    expect(find.text('7'), findsOneWidget);
    expect(find.byIcon(Icons.notifications), findsOneWidget);

    api.rows = [for (var i = 1; i <= 120; i++) notificationJson(id: i, readAt: null)];
    await c.load();
    await tester.pump();
    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('tapping the bell opens the list: rows, the tone tag, the ack button only on scored rows, mark all read', (tester) async {
    final api = FakeNotificationsApi([
      notificationJson(id: 3, type: 'missing_clock_out_2', tone: 'urgent', title: 'Action needed for 2026-09-11', message: 'Recorded as **absent**', ackDeadlineAt: '2099-01-01T00:00:00.000Z'),
      notificationJson(id: 2, title: 'An FYI', message: 'No window', ackDeadlineAt: null, readAt: '2026-09-11T00:18:00.000Z'),
    ]);
    final c = await pumpBell(tester, api);
    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Action needed for 2026-09-11'), findsOneWidget);
    expect(find.text('Recorded as absent'), findsOneWidget, reason: 'markdown stripped');
    expect(find.text('Action needed'), findsOneWidget, reason: 'the urgent tag');
    expect(find.text("I've got this"), findsOneWidget, reason: 'only the scored row');
    expect(find.text('An FYI'), findsOneWidget);
    expect(find.textContaining('Respond by'), findsOneWidget);

    await tester.tap(find.text("I've got this"));
    await tester.pumpAndSettle();
    expect(api.calls, contains('ack:3'));
    expect(find.text('Acknowledged'), findsOneWidget);
    expect(find.text('Acknowledged.'), findsOneWidget); // the snackbar
    expect(c.unreadCount, 0);
    expect(find.text('Mark all read'), findsNothing);

    api.rows.add(notificationJson(id: 4, readAt: null));
    await c.load();
    await tester.pump();
    expect(find.text('Mark all read'), findsOneWidget);
    await tester.tap(find.text('Mark all read'));
    await tester.pump();
    expect(api.calls.last, 'read-all');
  });

  testWidgets('the empty state explains where reminders come from', (tester) async {
    final c = await pumpBell(tester, FakeNotificationsApi([]));
    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();
    expect(find.text('No reminders'), findsOneWidget);
    expect(find.textContaining('set by HR'), findsOneWidget);
    c.dispose();
  });

  testWidgets('the Time Clock tells the reminders after every status load', (tester) async {
    final api = FakeClockApi();
    final sync = FakeReminderSync();
    final c = TimeClockController(api: api, fixes: FakeFixService(), reminders: sync);
    await c.load();
    expect(sync.statuses.single.localDate, '2026-09-11');
    await c.punch('in', capture: FakeFaceCapturer().call);
    expect(sync.statuses.length, 2);
  });

  group('Settings › Clock reminders tile', () {
    testWidgets('renders nothing when the reminders are not provided (a shell test)', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ClockRemindersTile())));
      await tester.pump();
      expect(find.text('Clock reminders'), findsNothing);
    });

    testWidgets('names the next armed reminder and offers Sync now', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final env = EnvStore();
      await env.load();
      final session = SessionController(env: env, store: InMemorySessionStore(), appVersion: '1');
      final store = InMemoryReminderStore();
      final scheduleApi = FakeReminderScheduleApi();
      final coordinator = ReminderCoordinator(
        session: session,
        store: store,
        scheduler: ReminderScheduler(store: store, alarms: FakeAlarmPort(), api: scheduleApi, now: () => DateTime.utc(2026, 9, 10, 23)),
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ReminderCoordinator?>.value(value: coordinator),
            Provider<DeviceReadinessService>.value(value: AlwaysReadyDevice()),
          ],
          child: MaterialApp(theme: buildTheme(Brightness.light), home: const Scaffold(body: ClockRemindersTile())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Clock reminders'), findsOneWidget);
      expect(find.text('Allow exact alarms'), findsNothing);
      // No button: opening the row re-planned on its own.
      expect(find.text('Sync now'), findsNothing);
      expect(scheduleApi.calls, 1);
      expect(find.text('Ready'), findsOneWidget);
      expect(find.textContaining('Next: clock-in reminder'), findsOneWidget);
      expect(store.armedAlarms.length, 5);
    });

    Future<void> pumpTile(WidgetTester tester, DeviceReadinessService device) async {
      SharedPreferences.setMockInitialValues({});
      final env = EnvStore();
      await env.load();
      final session = SessionController(env: env, store: InMemorySessionStore(), appVersion: '1');
      final store = InMemoryReminderStore();
      final coordinator = ReminderCoordinator(
        session: session,
        store: store,
        scheduler: ReminderScheduler(store: store, alarms: FakeAlarmPort(), api: FakeReminderScheduleApi()),
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ReminderCoordinator?>.value(value: coordinator),
            Provider<DeviceReadinessService>.value(value: device),
          ],
          child: MaterialApp(theme: buildTheme(Brightness.light), home: const Scaffold(body: ClockRemindersTile())),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('exact alarms off → Needs attention with the brand\'s steps, and NO button (no dialog can set it)', (tester) async {
      await pumpTile(tester, _NoExactAlarms('samsung'));
      expect(find.text('Needs attention'), findsOneWidget);
      expect(find.textContaining('Exact alarms are off'), findsOneWidget);
      expect(find.text('To allow exact alarms on your Samsung phone:'), findsOneWidget);
      expect(find.textContaining('Special access › Alarms and reminders'), findsOneWidget);
      expect(find.textContaining('Find HRIS in the list'), findsOneWidget);
      expect(find.text('Allow exact alarms'), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('a brand whose menus move between versions gets Settings search, not a guessed path', (tester) async {
      await pumpTile(tester, _NoExactAlarms('HONOR'));
      expect(find.text('To allow exact alarms on your HUAWEI / HONOR phone:'), findsOneWidget);
      expect(find.textContaining('type "alarms"'), findsOneWidget);
      expect(find.textContaining('Special access'), findsNothing);
    });

    testWidgets('exact alarms allowed (every Android 13+ phone) → no steps at all', (tester) async {
      await pumpTile(tester, AlwaysReadyDevice());
      expect(find.textContaining('To allow exact alarms'), findsNothing);
      expect(find.text('Needs attention'), findsNothing);
    });
  });
}
