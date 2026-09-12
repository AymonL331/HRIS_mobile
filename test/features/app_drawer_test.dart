import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/features/shell/app_drawer.dart';
import 'package:hris_mobile/shared/theme.dart';
import 'package:hris_mobile/shared/tokens.dart';

const _sections = [
  NavSection('Self-Service', [
    NavDestination(index: 0, label: 'Time Clock', icon: Icons.punch_clock_outlined, selectedIcon: Icons.punch_clock),
    NavDestination(index: 1, label: 'Attendance', icon: Icons.calendar_month_outlined, selectedIcon: Icons.calendar_month),
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
  await tester.pumpWidget(MaterialApp(
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
  ));
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
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        key: key,
        drawer: AppDrawer(
          sections: _sections,
          selectedIndex: 0,
          onSelect: (i) => picked = i,
          username: 'sofia',
        ),
        body: const SizedBox(),
      ),
    ));
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

    final ink = tester.widget<Ink>(
      find.ancestor(of: find.text('My Payslips'), matching: find.byType(Ink)),
    );
    expect((ink.decoration as BoxDecoration).color, t.primarySoft);
  });

  testWidgets('the sidebar follows dark mode', (tester) async {
    await pumpDrawer(tester, selected: 1, brightness: Brightness.dark);
    final label = tester.widget<Text>(find.text('Attendance'));
    expect(label.style!.color, HrisTokens.dark.primary);
    final inactive = tester.widget<Text>(find.text('Settings'));
    expect(inactive.style!.color, HrisTokens.dark.text);
  });

  testWidgets('an account with no role name still renders', (tester) async {
    await pumpDrawer(tester, roleName: null);
    expect(find.text('sofia'), findsOneWidget);
    expect(find.text('Employee'), findsNothing);
  });
}
