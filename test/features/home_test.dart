import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/http/api_exception.dart';
import 'package:hris_mobile/features/home/home_api.dart';
import 'package:hris_mobile/features/home/home_models.dart';
import 'package:hris_mobile/features/home/home_screen.dart';

class FakeHomeApi implements HomeApi {
  Map<String, dynamic> json = {};
  ApiException? error;
  int calls = 0;

  @override
  Future<MyDashboard> dashboard() async {
    calls++;
    if (error != null) throw error!;
    return MyDashboard.fromJson(json);
  }
}

Map<String, dynamic> summary({bool empty = false}) => {
      'employee_id': 5,
      'leave': {
        'year': 2026,
        'balances': empty
            ? []
            : [
                {'leave_type_id': 1, 'leave_type': 'Vacation Leave', 'accrued': 5, 'used': 1, 'remaining': 4},
                {'leave_type_id': 2, 'leave_type': 'Sick Leave', 'accrued': 5, 'used': 0, 'remaining': 5.5},
              ],
        'total_remaining': empty ? 0 : 9.5,
      },
      'latest_payslip': empty
          ? null
          : {'id': 294, 'net_pay': 5947, 'status': 'released', 'period_start': '2026-11-01', 'period_end': '2026-11-15'},
      'pending_requests': empty
          ? {'leave': 0, 'corrections': 0, 'travel_orders': 0, 'total': 0}
          : {'leave': 1, 'corrections': 2, 'travel_orders': 0, 'total': 3},
      'unread_notifications': 0,
      'upcoming_holidays': empty
          ? []
          : [
              {'id': 9, 'title': 'Bonifacio Day', 'date': '2026-11-30', 'type': 'regular'},
            ],
    };

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('shows the four cards with the web wording and figures', (tester) async {
    final api = FakeHomeApi()..json = summary();
    await tester.pumpWidget(host(HomeScreen(api: api, username: 'grace')));
    await tester.pumpAndSettle();

    expect(find.text('Welcome, grace'), findsOneWidget);
    expect(find.text('Your self-service home.'), findsOneWidget);
    expect(find.text('My leave balance'), findsOneWidget);
    expect(find.text('9.5'), findsOneWidget);
    expect(find.text('days left'), findsOneWidget);
    expect(find.text('Vacation Leave'), findsOneWidget);
    expect(find.text('My latest payslip'), findsOneWidget);
    expect(find.text('₱5,947.00'), findsOneWidget);
    expect(find.text('Nov 1, 2026 – Nov 15, 2026'), findsOneWidget);
    expect(find.text('Released'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('My pending requests'), 200);
    expect(find.text('awaiting approval'), findsOneWidget);
    expect(find.text('DTR corrections'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Bonifacio Day'), 200);
    expect(find.text('Upcoming holidays'), findsOneWidget);
    expect(find.text('Nov 30, 2026'), findsOneWidget);
  });

  testWidgets('honest empty states', (tester) async {
    final api = FakeHomeApi()..json = summary(empty: true);
    await tester.pumpWidget(host(HomeScreen(api: api, username: 'grace')));
    await tester.pumpAndSettle();
    expect(find.text('No leave balances set up for 2026 yet.'), findsOneWidget);
    expect(find.text('No payslip has been issued to you yet.'), findsOneWidget);
    expect(find.text('Nothing awaiting approval.'), findsOneWidget);
    expect(find.text('No upcoming holidays on the company calendar.'), findsOneWidget);
    expect(find.text('View payslip →'), findsNothing);
  });

  testWidgets('links navigate like the web', (tester) async {
    final api = FakeHomeApi()..json = summary();
    final went = <String>[];
    int? opened;
    await tester.pumpWidget(host(HomeScreen(api: api, username: 'g', onNavigate: went.add, onOpenPayslip: (id) => opened = id)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage my leave →'));
    await tester.tap(find.text('View payslip →'));
    await tester.scrollUntilVisible(find.text('My attendance →'), 200);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('My attendance →'));
    await tester.tap(find.text('My attendance →'));
    expect(went, ['leave', 'attendance']);
    expect(opened, 294);
  });

  testWidgets('error then Try again', (tester) async {
    final api = FakeHomeApi()..error = const ApiException(status: 500, message: 'Server down');
    await tester.pumpWidget(host(HomeScreen(api: api, username: 'g')));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load your summary"), findsOneWidget);
    expect(find.text('Server down'), findsOneWidget);
    api
      ..error = null
      ..json = summary();
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('My leave balance'), findsOneWidget);
  });

  testWidgets('loads only when active, again on each opening', (tester) async {
    final api = FakeHomeApi()..json = summary();
    await tester.pumpWidget(host(HomeScreen(api: api, username: 'g', active: false)));
    await tester.pumpAndSettle();
    expect(api.calls, 0);
    await tester.pumpWidget(host(HomeScreen(api: api, username: 'g')));
    await tester.pumpAndSettle();
    expect(api.calls, 1);
    await tester.pumpWidget(host(HomeScreen(api: api, username: 'g', active: false)));
    await tester.pumpWidget(host(HomeScreen(api: api, username: 'g')));
    await tester.pumpAndSettle();
    expect(api.calls, 2);
  });
}
