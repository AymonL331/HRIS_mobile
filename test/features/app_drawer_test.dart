import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/auth/session_controller.dart';
import 'package:hris_mobile/core/auth/session_store.dart';
import 'package:hris_mobile/core/config/env_store.dart';
import 'package:hris_mobile/features/shell/app_drawer.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hris_mobile/shared/theme.dart';
import 'package:hris_mobile/shared/tokens.dart';

const _sections = [
  NavSection('Self-Service', [
    NavDestination(index: 0, label: 'Time Clock', icon: Icons.punch_clock_outlined, selectedIcon: Icons.punch_clock),
    NavDestination(
      index: 1,
      label: 'Attendance',
      icon: Icons.calendar_month_outlined,
      selectedIcon: Icons.calendar_month,
    ),
    NavDestination(index: 2, label: 'My Payslips', icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long),
  ]),
  NavSection('Account', [
    NavDestination(index: 3, label: 'Settings', icon: Icons.settings_outlined, selectedIcon: Icons.settings),
  ]),
];

/// Mounts the drawer open, the way the shell shows it.
Future<void> pumpDrawer(
  WidgetTester tester, {
  int selected = 0,
  Brightness brightness = Brightness.light,
  String username = 'sofia',
  String? roleName = 'Employee',
}) async {
  final key = GlobalKey<ScaffoldState>();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(brightness),
      home: Scaffold(
        key: key,
        drawer: AppDrawer(
          sections: _sections,
          selectedIndex: selected,
          onSelect: (_) {},
          username: username,
          roleName: roleName,
        ),
        body: const SizedBox(),
      ),
    ),
  );
  key.currentState!.openDrawer();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the sidebar lists every destination under its section label', (tester) async {
    await pumpDrawer(tester);
    // The web sidebar's uppercase .sectionTitle.
    expect(find.text('SELF-SERVICE'), findsOneWidget);
    expect(find.text('ACCOUNT'), findsOneWidget);
    expect(find.text('Time Clock'), findsOneWidget);
    expect(find.text('Attendance'), findsOneWidget);
    expect(find.text('My Payslips'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    // The brand block, and who is signed in.
    expect(find.text('HRIS'), findsOneWidget);
    expect(find.text('sofia'), findsOneWidget);
    expect(find.text('Employee'), findsOneWidget);
  });

  testWidgets('picking a destination reports its index and closes the drawer', (tester) async {
    int? picked;
    final key = GlobalKey<ScaffoldState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          key: key,
          drawer: AppDrawer(sections: _sections, selectedIndex: 0, onSelect: (i) => picked = i, username: 'sofia'),
          body: const SizedBox(),
        ),
      ),
    );
    key.currentState!.openDrawer();
    await tester.pumpAndSettle();

    await tester.tap(find.text('My Payslips'));
    await tester.pumpAndSettle();

    expect(picked, 2);
    // A drawer that stays open over the page it just opened is a bug, not a nav.
    expect(find.text('SELF-SERVICE'), findsNothing);
  });

  testWidgets('the active item wears primary-soft with primary text, as .itemActive does', (tester) async {
    await pumpDrawer(tester, selected: 2);
    final t = HrisTokens.light;

    final label = tester.widget<Text>(find.text('My Payslips'));
    expect(label.style!.color, t.primary);
    expect(label.style!.fontWeight, HrisType.semibold);

    // …and an inactive one does not.
    final other = tester.widget<Text>(find.text('Time Clock'));
    expect(other.style!.color, t.text);

    final ink = tester.widget<Ink>(find.ancestor(of: find.text('My Payslips'), matching: find.byType(Ink)));
    expect((ink.decoration as BoxDecoration).color, t.primarySoft);
  });

  testWidgets('the sidebar follows dark mode', (tester) async {
    await pumpDrawer(tester, selected: 1, brightness: Brightness.dark);
    final label = tester.widget<Text>(find.text('Attendance'));
    expect(label.style!.color, HrisTokens.dark.primary);
    final inactive = tester.widget<Text>(find.text('Settings'));
    expect(inactive.style!.color, HrisTokens.dark.text);
  });

  testWidgets('Sign out is pinned to the footer, in the danger tone, and closes the drawer when tapped', (
    tester,
  ) async {
    var signOuts = 0;
    final key = GlobalKey<ScaffoldState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          key: key,
          drawer: AppDrawer(
            sections: _sections,
            selectedIndex: 0,
            onSelect: (_) {},
            username: 'sofia',
            onSignOut: () => signOuts++,
          ),
          body: const SizedBox(),
        ),
      ),
    );
    key.currentState!.openDrawer();
    await tester.pumpAndSettle();

    // Below every destination — the footer, not another row after Settings.
    final signOutTop = tester.getTopLeft(find.text('Sign out')).dy;
    expect(
      signOutTop,
      greaterThan(tester.getTopLeft(find.text('Settings')).dy + 200),
      reason: 'pinned to the bottom, well apart from the last destination',
    );
    expect(tester.widget<Text>(find.text('Sign out')).style!.color, HrisTokens.light.danger.text);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(signOuts, 1);
    expect(find.text('SELF-SERVICE'), findsNothing);
  });

  testWidgets('no sign-out handler, no footer', (tester) async {
    await pumpDrawer(tester);
    expect(find.text('Sign out'), findsNothing);
  });

  testWidgets('confirmSignOut asks first: Cancel keeps the session, Sign out ends it', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final env = EnvStore();
    await env.load();
    final store = InMemorySessionStore();
    await store.write(env.config.storageKey, const SessionRecord(token: 't'));
    final session = SessionController(env: env, store: store, appVersion: '1');

    await tester.pumpWidget(
      ChangeNotifierProvider<SessionController>.value(
        value: session,
        child: MaterialApp(
          theme: buildTheme(),
          home: Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(onPressed: () => confirmSignOut(ctx), child: const Text('open')),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await store.read(env.config.storageKey), isNotNull, reason: 'Cancel must not sign out');

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();
    expect(await store.read(env.config.storageKey), isNull);
    expect(session.state, isA<SignedOut>());
  });

  testWidgets('an account with no role name still renders', (tester) async {
    await pumpDrawer(tester, roleName: null);
    expect(find.text('sofia'), findsOneWidget);
    expect(find.text('Employee'), findsNothing);
  });
}
