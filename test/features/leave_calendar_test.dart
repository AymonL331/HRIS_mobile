import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/http/api_exception.dart';
import 'package:hris_mobile/features/leave_calendar/leave_calendar_api.dart';
import 'package:hris_mobile/features/leave_calendar/leave_calendar_models.dart';
import 'package:hris_mobile/features/leave_calendar/leave_calendar_month.dart';
import 'package:hris_mobile/features/leave_calendar/leave_calendar_screen.dart';

class FakeLeaveCalendarApi implements LeaveCalendarApi {
  Map<String, dynamic> json = {};
  Map<String, dynamic> peopleJson = {'items': [], 'truncated': false};
  ApiException? error;
  final calls = <Map<String, String>>[];
  final peopleCalls = <Map<String, String>>[];

  @override
  Future<LeaveCalendarData> get({
    required String scope,
    required String from,
    required String to,
    String branchId = '',
    String employeeId = '',
  }) async {
    calls.add({'scope': scope, 'from': from, 'to': to, 'branch_id': branchId, 'employee_id': employeeId});
    if (error != null) throw error!;
    return LeaveCalendarData.fromJson(json);
  }

  @override
  Future<CalendarPeople> people({required String scope, String branchId = '', String search = ''}) async {
    peopleCalls.add({'scope': scope, 'branch_id': branchId, 'search': search});
    return CalendarPeople.fromJson(peopleJson);
  }
}

Map<String, dynamic> leave(int id, String name, String from, String to, {String status = 'approved', bool self = false}) => {
      'id': id,
      'employee_id': id,
      'employee_code': 'E$id',
      'employee_name': name,
      'branch_id': 1,
      'branch_name': 'Daet',
      'leave_type_id': 1,
      'leave_type_name': 'Vacation Leave',
      'date_from': from,
      'date_to': to,
      'days': '2.00',
      'status': status,
      'is_self': self,
    };

Map<String, dynamic> calendar({Map<String, bool>? scopes, List<Map<String, dynamic>>? leaves, bool truncated = false}) => {
      'scope': 'branch',
      'available_scopes': scopes ?? {'self': true, 'branch': true, 'all': false},
      'available_branches': [
        {'id': 1, 'name': 'Daet'},
      ],
      'leaves': leaves ??
          [
            leave(1, 'Ana Cruz', '2026-11-10', '2026-11-11', self: true),
            leave(2, 'Ben Dela', '2026-11-10', '2026-11-10', status: 'pending'),
            leave(3, 'Cara Diaz', '2026-11-10', '2026-11-10'),
            leave(4, 'Dan Uy', '2026-11-10', '2026-11-10'),
          ],
      'holidays': [
        {'id': 7, 'title': 'Bonifacio Day', 'date': '2026-11-30', 'type': 'regular', 'paid': true, 'branch_id': null, 'branch_name': null, 'company_wide': true},
      ],
      'truncated': truncated,
    };

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));
final today = DateTime(2026, 11, 23);

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(1080, 5000);
    binding.platformDispatcher.views.first.devicePixelRatio = 2.5;
  });
  tearDown(() => TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first.resetPhysicalSize());

  test('month grid: Sunday-first whole weeks, the API window, spans on every day', () {
    final cells = buildMonthGrid(const MonthRef(2026, 11));
    expect(cells.first.key, '2026-11-01'); // Nov 1 2026 is a Sunday
    expect(cells.last.key, '2026-12-05');
    expect(cells.length % 7, 0);
    expect(gridRange(const MonthRef(2026, 10)), (from: '2026-09-27', to: '2026-10-31'));
    final byDay = indexByDay(
      LeaveCalendarData.fromJson({'leaves': [leave(1, 'A', '2026-10-30', '2026-11-02')], 'holidays': []}),
      '2026-11-01',
      '2026-12-05',
    );
    expect(byDay.keys.toList(), ['2026-11-01', '2026-11-02']);
  });

  testWidgets('an account without "all" is stepped down to the widest scope the server offers', (tester) async {
    final api = FakeLeaveCalendarApi()..json = calendar();
    await tester.pumpWidget(host(LeaveCalendarScreen(api: api, today: today)));
    await tester.pumpAndSettle();

    expect(api.calls.map((c) => c['scope']).toList(), ['all', 'branch']);
    expect(api.calls.first['from'], '2026-11-01');
    expect(api.calls.first['to'], '2026-12-05');
    expect(find.text('My leave'), findsOneWidget);
    expect(find.text('My branch'), findsOneWidget);
    expect(find.text('All employees'), findsNothing);
    // One branch is not a choice.
    expect(find.text('All branches'), findsNothing);
    expect(find.text('November 2026'), findsOneWidget);
    expect(find.text('4 leave records this period'), findsOneWidget);
    expect(find.text('Rejected and cancelled leave is not shown.'), findsOneWidget);
    expect(find.text('Bonifacio Day'), findsOneWidget);
    expect(find.text('+1 more'), findsOneWidget);
    expect(find.text('Select a day to see who is away.'), findsOneWidget);
  });

  testWidgets('tapping a day lists everyone away, with (you), never a reason', (tester) async {
    final api = FakeLeaveCalendarApi()..json = calendar();
    await tester.pumpWidget(host(LeaveCalendarScreen(api: api, today: today)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('leave_day_2026-11-10')));
    await tester.pumpAndSettle();
    expect(find.text('Nov 10, 2026'), findsOneWidget);
    expect(find.text('Ana Cruz (you)', findRichText: true), findsOneWidget);
    expect(find.textContaining('(you)', findRichText: true), findsOneWidget);
    expect(find.text('Ben Dela', findRichText: true), findsOneWidget);
    expect(find.text('Dan Uy', findRichText: true), findsOneWidget);
    expect(find.text('Nov 10, 2026 – Nov 11, 2026 · 2 days'), findsOneWidget);
    expect(find.text('Pending'), findsNWidgets(2)); // legend + badge
    expect(find.text('Approved'), findsNWidgets(4)); // legend + 3 badges

    await tester.tap(find.byKey(const Key('leave_day_2026-11-30')));
    await tester.pumpAndSettle();
    expect(find.text('Regular holiday · All branches'), findsOneWidget);

    await tester.tap(find.byKey(const Key('leave_day_2026-11-05')));
    await tester.pumpAndSettle();
    expect(find.text('Nobody is on leave this day.'), findsOneWidget);

    // Tapping the open day again closes it.
    await tester.tap(find.byKey(const Key('leave_day_2026-11-05')));
    await tester.pumpAndSettle();
    expect(find.text('Select a day to see who is away.'), findsOneWidget);
  });

  testWidgets('month steps ask for the new window and clear the picked day; Today comes back', (tester) async {
    final api = FakeLeaveCalendarApi()..json = calendar(scopes: {'self': true, 'branch': true, 'all': true}, leaves: []);
    await tester.pumpWidget(host(LeaveCalendarScreen(api: api, today: today)));
    await tester.pumpAndSettle();
    expect(find.text('No leave filed for this period.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('leave_day_2026-11-05')));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Next month'));
    await tester.pumpAndSettle();
    expect(find.text('December 2026'), findsOneWidget);
    expect(api.calls.last['from'], '2026-11-29');
    expect(api.calls.last['to'], '2027-01-02');
    expect(find.text('Select a day to see who is away.'), findsOneWidget);

    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.text('November 2026'), findsOneWidget);
  });

  testWidgets('employee picker searches the server and narrows the calendar; My leave locks it', (tester) async {
    final api = FakeLeaveCalendarApi()
      ..json = calendar(scopes: {'self': true, 'branch': true, 'all': true})
      ..peopleJson = {
        'items': [
          {'id': 2, 'employee_code': 'E2', 'name': 'Ben Dela', 'branch_id': 1, 'branch_name': 'Daet'},
        ],
        'truncated': true,
      };
    await tester.pumpWidget(host(LeaveCalendarScreen(api: api, today: today)));
    await tester.pumpAndSettle();

    expect(find.text('Everyone — or search a name'), findsOneWidget);
    await tester.tap(find.byKey(const Key('leave_calendar_employee')));
    await tester.pumpAndSettle();
    expect(find.text('Showing the first matches — type a name to narrow the list.'), findsOneWidget);
    expect(find.text('E2 · Daet'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('leave_calendar_search')), 'ben');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(api.peopleCalls.last, {'scope': 'all', 'branch_id': '', 'search': 'ben'});
    await tester.tap(find.text('Ben Dela').last);
    await tester.pumpAndSettle();
    expect(api.calls.last['employee_id'], '2');

    await tester.tap(find.text('My leave'));
    await tester.pumpAndSettle();
    expect(api.calls.last['scope'], 'self');
    expect(api.calls.last['employee_id'], '');
    expect(find.text('Only me'), findsOneWidget);
  });

  testWidgets('truncated period warns; a failed first load shows the error with Try again', (tester) async {
    final api = FakeLeaveCalendarApi()..json = calendar(scopes: {'self': true, 'branch': true, 'all': true}, truncated: true);
    await tester.pumpWidget(host(LeaveCalendarScreen(api: api, today: today)));
    await tester.pumpAndSettle();
    expect(
      find.text('This period has more records than the calendar can show at once. Narrow the view with the filters above to see them all.'),
      findsOneWidget,
    );

    final bad = FakeLeaveCalendarApi()..error = const ApiException(status: 500, message: 'Server down');
    await tester.pumpWidget(host(LeaveCalendarScreen(key: const Key('b'), api: bad, today: today)));
    await tester.pumpAndSettle();
    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Server down'), findsOneWidget);
    bad
      ..error = null
      ..json = calendar(scopes: {'self': true, 'branch': true, 'all': true}, leaves: []);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('No leave filed for this period.'), findsOneWidget);
  });
}
