import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/http/api_exception.dart';
import 'package:hris_mobile/features/leave/leave_api.dart';
import 'package:hris_mobile/features/leave/leave_models.dart';
import 'package:hris_mobile/features/leave/leave_screen.dart';

class FakeLeaveApi implements LeaveApi {
  List<Map<String, dynamic>> rows = [];
  Map<String, dynamic> pagination = {'page': 1, 'limit': 20, 'total': 0, 'totalPages': 1};
  List<Map<String, dynamic>> balanceRows = [];
  List<Map<String, dynamic>> typeRows = [
    {'id': 1, 'name': 'Vacation Leave', 'payment_type': 'paid'},
    {'id': 2, 'name': 'Sick Leave', 'payment_type': 'unpaid'},
  ];
  ApiException? listError;
  ApiException? submitError;
  ApiException? cancelError;
  final pages = <int>[];
  final submitted = <Map<String, dynamic>>[];
  final cancelled = <int>[];

  @override
  Future<LeaveRequestPage> listRequests({int page = 1}) async {
    pages.add(page);
    if (listError != null) throw listError!;
    return LeaveRequestPage.fromJson({'items': rows, 'pagination': {...pagination, 'page': page}});
  }

  @override
  Future<List<LeaveBalance>> balances() async => balanceRows.map(LeaveBalance.fromJson).toList();

  @override
  Future<List<LeaveType>> types() async => typeRows.map(LeaveType.fromJson).toList();

  @override
  Future<void> submit(Map<String, dynamic> payload) async {
    if (submitError != null) throw submitError!;
    submitted.add(payload);
  }

  @override
  Future<void> cancel(int id) async {
    if (cancelError != null) throw cancelError!;
    cancelled.add(id);
  }
}

Map<String, dynamic> req(int id, String status, {String from = '2026-11-03', String to = '2026-11-05', String days = '3.00', String part = 'full', int type = 1}) =>
    {'id': id, 'leave_type_id': type, 'date_from': from, 'date_to': to, 'day_part': part, 'days': days, 'status': status};

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(1080, 4000);
    binding.platformDispatcher.views.first.devicePixelRatio = 2.5;
  });
  tearDown(() => TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first.resetPhysicalSize());

  test('JS Number text: decimals trimmed like the web', () {
    expect(jsNumber('3.00'), '3');
    expect(jsNumber('0.50'), '0.5');
    expect(jsNumber(15), '15');
    expect(LeaveRequestRow.fromJson(req(1, 'pending', days: '0.50', part: 'am_half')).daysLabel, '0.5 (AM)');
    expect(LeaveRequestRow.fromJson(req(1, 'pending', days: '0.50', part: 'pm_half')).daysLabel, '0.5 (PM)');
  });

  testWidgets('balances, requests with status and Cancel only for pending (not once approved), paging line', (tester) async {
    final api = FakeLeaveApi()
      ..balanceRows = [
        {'id': 9, 'leave_type_id': 1, 'year': 2026, 'accrued': '5.00', 'used': '1.50', 'remaining': '3.50'},
      ]
      ..rows = [
        req(1, 'pending'),
        req(2, 'approved', type: 2, from: '2026-10-10', to: '2026-10-10', days: '0.50', part: 'pm_half'),
        req(3, 'rejected', type: 7),
        req(4, 'cancelled'),
      ]
      ..pagination = {'page': 1, 'limit': 20, 'total': 4, 'totalPages': 1};
    await tester.pumpWidget(host(MyLeaveScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('File leave and track your requests.'), findsOneWidget);
    expect(find.text('File leave'), findsOneWidget);
    expect(find.text('3.5'), findsOneWidget);
    expect(find.text('days left · 1.5 used of 5 (2026)'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.text('Leave type #7'), findsOneWidget);
    expect(find.text('Days 0.5 (PM)'), findsOneWidget);
    expect(find.text('From Nov 3, 2026 · To Nov 5, 2026'), findsNWidgets(3));
    expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    expect(find.text('Page 1 of 1 · 4 total'), findsOneWidget);
    final prev = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Previous'));
    expect(prev.onPressed, isNull);
  });

  testWidgets('Next loads page 2', (tester) async {
    final api = FakeLeaveApi()
      ..rows = [req(1, 'pending')]
      ..pagination = {'page': 1, 'limit': 20, 'total': 25, 'totalPages': 2};
    await tester.pumpWidget(host(MyLeaveScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();
    expect(api.pages, [1, 2]);
    expect(find.text('Page 2 of 2 · 25 total'), findsOneWidget);
  });

  testWidgets('empty and error states use the web words', (tester) async {
    final api = FakeLeaveApi();
    await tester.pumpWidget(host(MyLeaveScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('No leave requests yet'), findsOneWidget);
    expect(find.text('Use File leave above — your requests will appear here.'), findsOneWidget);

    final bad = FakeLeaveApi()..listError = const ApiException(status: 500, message: 'Server down');
    await tester.pumpWidget(host(MyLeaveScreen(key: const Key('b'), api: bad)));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load your leave"), findsOneWidget);
    expect(find.text('Server down'), findsOneWidget);
    bad.listError = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('No leave requests yet'), findsOneWidget);
  });

  testWidgets('not active: nothing loads until the page is opened', (tester) async {
    final api = FakeLeaveApi();
    await tester.pumpWidget(host(MyLeaveScreen(api: api, active: false)));
    await tester.pump();
    expect(api.pages, isEmpty);
    await tester.pumpWidget(host(MyLeaveScreen(api: api, active: true)));
    await tester.pumpAndSettle();
    expect(api.pages, [1]);
  });

  Future<void> pickDay(WidgetTester tester, String fieldKey, String day) async {
    await tester.tap(find.byKey(Key(fieldKey)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(day).last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  testWidgets('File leave: required checks, half day only for one date, exact body, banner', (tester) async {
    final api = FakeLeaveApi();
    await tester.pumpWidget(host(MyLeaveScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('File leave'));
    await tester.pumpAndSettle();

    expect(find.text('File a leave request'), findsOneWidget);
    expect(find.text('Your request is submitted for approval. The number of days is calculated from the dates.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('leave_submit')));
    await tester.pumpAndSettle();
    expect(find.text('Select a leave type.'), findsOneWidget);
    expect(find.text('Select a start date.'), findsOneWidget);
    expect(find.text('Select an end date.'), findsOneWidget);
    expect(find.text('Half-day applies only when the start and end date are the same day.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('leave_type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sick Leave (Unpaid)').last);
    await tester.pumpAndSettle();

    // End before start → the web's message.
    await pickDay(tester, 'leave_date_from', '15');
    await pickDay(tester, 'leave_date_to', '14');
    await tester.tap(find.byKey(const Key('leave_submit')));
    await tester.pumpAndSettle();
    expect(find.text('End date cannot be before the start date.'), findsOneWidget);

    // One date → the half-day selector opens.
    await pickDay(tester, 'leave_date_to', '15');
    expect(find.text('A morning/afternoon half files 0.5 day.'), findsOneWidget);
    await tester.tap(find.text('Full day'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Morning half (AM)').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('leave_reason')), '  Check-up  ');
    await tester.tap(find.byKey(const Key('leave_submit')));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    final d = '${now.year}-${now.month.toString().padLeft(2, '0')}-15';
    expect(api.submitted.single, {'leave_type_id': 2, 'date_from': d, 'date_to': d, 'day_part': 'am_half', 'reason': 'Check-up'});
    expect(find.text('Leave request submitted.'), findsOneWidget);
  });

  testWidgets('a widened range falls back to full day; server field errors show under the field', (tester) async {
    final api = FakeLeaveApi()
      ..submitError = const ApiException(status: 422, message: 'Validation failed.', fieldErrors: {'date_from': 'Overlaps another request.'});
    await tester.pumpWidget(host(MyLeaveScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('File leave'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('leave_type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vacation Leave (Paid)').last);
    await tester.pumpAndSettle();
    await pickDay(tester, 'leave_date_from', '10');
    await pickDay(tester, 'leave_date_to', '10');
    await tester.tap(find.text('Full day'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Afternoon half (PM)').last);
    await tester.pumpAndSettle();
    await pickDay(tester, 'leave_date_to', '12');
    expect(find.text('Full day'), findsOneWidget);
    await tester.tap(find.byKey(const Key('leave_submit')));
    await tester.pumpAndSettle();
    expect(find.text('Overlaps another request.'), findsOneWidget);
    expect(find.text('File a leave request'), findsOneWidget);
  });

  testWidgets('Cancel asks first, then cancels and says so; a failure is shown', (tester) async {
    final api = FakeLeaveApi()..rows = [req(5, 'pending')];
    await tester.pumpWidget(host(MyLeaveScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel this leave request?'), findsOneWidget);
    expect(find.text("Vacation Leave, Nov 3, 2026 – Nov 5, 2026. This can't be undone."), findsOneWidget);
    await tester.tap(find.text('Keep it'));
    await tester.pumpAndSettle();
    expect(api.cancelled, isEmpty);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel request'));
    await tester.pumpAndSettle();
    expect(api.cancelled, [5]);
    expect(find.text('Leave request cancelled.'), findsOneWidget);

    api.cancelError = const ApiException(status: 422, message: 'Only pending or approved requests can be cancelled.');
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel request'));
    await tester.pumpAndSettle();
    expect(find.text('Only pending or approved requests can be cancelled.'), findsOneWidget);
  });
}
