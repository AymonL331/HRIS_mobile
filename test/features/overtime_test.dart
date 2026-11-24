import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/http/api_exception.dart';
import 'package:hris_mobile/features/attendance/correction_form_screen.dart' show PickedProof;
import 'package:hris_mobile/features/overtime/overtime_api.dart';
import 'package:hris_mobile/features/overtime/overtime_files.dart';
import 'package:hris_mobile/features/overtime/overtime_models.dart';
import 'package:hris_mobile/features/overtime/overtime_request_screen.dart';
import 'package:hris_mobile/features/overtime/overtime_screen.dart';
import 'package:image_picker/image_picker.dart';

final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4]);

class FakeOvertimeApi implements OvertimeApi {
  List<Map<String, dynamic>> rows = [];
  Map<String, dynamic> pagination = {'page': 1, 'limit': 20, 'total': 0, 'totalPages': 1};
  Map<String, dynamic> windowJson = {};
  Map<String, dynamic> reportJson = {};
  ApiException? submitError;
  final calls = <String>[];
  final submitted = <Map<String, dynamic>>[];
  final requirements = <Map<String, dynamic>>[];
  final accomplishments = <Map<String, dynamic>>[];
  final windows = <String>[];

  @override
  Future<OvertimePage> list({int page = 1}) async {
    calls.add('list $page');
    return OvertimePage.fromJson({'items': rows, 'pagination': pagination});
  }

  @override
  Future<OvertimeIdentity> identity() async => OvertimeIdentity.fromJson({
        'first_name': 'Daryl',
        'last_name': 'Vito',
        'department_name': 'Finance',
        'designation_name': 'Accounting Staff',
      });

  @override
  Future<OvertimeWindow> window({num? hours, List<String> dates = const []}) async {
    windows.add('${hours ?? ''}|${dates.join(',')}');
    return OvertimeWindow.fromJson(windowJson);
  }

  @override
  Future<String> stageForm(PickedProof file) async {
    calls.add('stage ${file.mimeType}');
    return '/api/uploads/overtime/form-${calls.length}.jpg';
  }

  @override
  Future<void> submit(Map<String, dynamic> payload) async {
    if (submitError != null) throw submitError!;
    submitted.add(payload);
  }

  @override
  Future<void> completeRequirements(int id, Map<String, dynamic> payload) async => requirements.add({'id': id, ...payload});

  @override
  Future<void> submitAccomplishment(int dateId, {String? note, List<PickedProof> photos = const []}) async =>
      accomplishments.add({'date': dateId, 'note': note, 'photos': photos.length});

  @override
  Future<OvertimeReport> report(int id) async => OvertimeReport.fromJson(reportJson);
}

Map<String, dynamic> filing({
  int id = 5,
  String status = 'approved',
  String otType = 'ordinary',
  List<Map<String, dynamic>>? dates,
  int outstanding = 1,
  int? assignedBy,
  String? purpose = 'Month-end closing',
  List<String> files = const [],
}) =>
    {
      'id': id,
      'status': status,
      'ot_type': otType,
      'ot_hours': '3.00',
      'start_time': '18:00:00',
      'end_time': '21:00:00',
      'purpose': purpose,
      'attachment_url': files.isEmpty ? null : files.first,
      'attachment_urls': files,
      'assigned_by': assignedBy,
      'assigned_by_name': assignedBy == null ? null : 'hradmin',
      'dates': dates ??
          [
            {'id': 51, 'date': '2026-11-20', 'accomplishment_at': null, 'accomplishment_note': null, 'photos': []},
            {
              'id': 52,
              'date': '2026-11-21',
              'accomplishment_at': '2026-11-21T14:05:00.000Z',
              'accomplishment_note': 'Closed the books',
              'photos': [
                {'id': 1, 'file_url': '/api/uploads/ot/a.jpg'},
              ],
            },
          ],
      'date_count': 2,
      'accomplishments_outstanding': outstanding,
    };

class FakePickers {
  static OvertimePickers jpg() => OvertimePickers(
        photo: (ImageSource _) async => PickedProof(bytes: jpeg, mimeType: 'image/jpeg', name: 'form.jpg'),
        pdf: () async => PickedProof(bytes: Uint8List.fromList([0x25, 0x50, 0x44, 0x46]), mimeType: 'application/pdf', name: 'form.pdf'),
      );
}

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(1080, 4800);
    binding.platformDispatcher.views.first.devicePixelRatio = 2.5;
  });
  tearDown(() => TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first.resetPhysicalSize());

  test('labels and formats match the web', () {
    expect(formatTimeOfDay('18:00:00'), '6:00 PM');
    expect(formatTimeOfDay('00:30:00'), '12:30 AM');
    expect(formatTimeOfDay(null), '');
    expect(hoursLabel('3.00'), '3 hours');
    expect(hoursLabel('1.00'), '1 hour');
    expect(hoursLabel('2.50'), '2.5 hours');
    expect(formatDateOnly('2026-11-20'), 'Nov 20, 2026');
    expect(formatDateOnly(null), '—');
    expect(isHolidayWork('regular_holiday'), isTrue);
    expect(isHolidayWork('rest_day'), isFalse);
    expect(otTypeLabels['special_holiday'], 'Special holiday');
  });

  testWidgets('empty: the web empty state and the File button', (tester) async {
    final api = FakeOvertimeApi();
    await tester.pumpWidget(host(OvertimeScreen(api: api, baseUrl: 'https://x')));
    await tester.pumpAndSettle();
    expect(find.text('File overtime or holiday work'), findsOneWidget);
    expect(find.text('No overtime or holiday work filed yet'), findsOneWidget);
    expect(api.calls, ['list 1']);
  });

  testWidgets('a hidden page loads nothing until it is opened', (tester) async {
    final api = FakeOvertimeApi();
    await tester.pumpWidget(host(OvertimeScreen(api: api, baseUrl: 'https://x', active: false)));
    await tester.pumpAndSettle();
    expect(api.calls, isEmpty);
    await tester.pumpWidget(host(OvertimeScreen(api: api, baseUrl: 'https://x', active: true)));
    await tester.pumpAndSettle();
    expect(api.calls, ['list 1']);
  });

  testWidgets('approved ordinary filing: gate note, report button, submitted row, outstanding', (tester) async {
    final api = FakeOvertimeApi()..rows = [filing()];
    await tester.pumpWidget(host(OvertimeScreen(api: api, baseUrl: 'https://x', today: '2026-11-23')));
    await tester.pumpAndSettle();

    expect(find.text('3 hours'), findsOneWidget);
    expect(find.text('6:00 PM – 9:00 PM'), findsOneWidget);
    expect(find.text('Ordinary day'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Month-end closing'), findsOneWidget);
    expect(find.textContaining('Paid only for the dates you clock out at 9:00 PM or later.'), findsOneWidget);
    expect(find.text('Report accomplishment'), findsOneWidget);
    expect(find.text('Accomplishment submitted'), findsOneWidget);
    expect(find.text('1 picture'), findsOneWidget);
    expect(find.text('1 of 2 still to report.'), findsOneWidget);
    expect(find.text('View accomplishment report'), findsOneWidget);

    // The submitted row opens the read-only view.
    await tester.tap(find.text('Accomplishment submitted'));
    await tester.pumpAndSettle();
    expect(find.text('Accomplishment for Nov 21, 2026'), findsOneWidget);
    expect(find.text('Closed the books'), findsOneWidget);
    expect(find.textContaining('· final'), findsOneWidget);
  });

  testWidgets('report an accomplishment inline: note + picture, then the list reloads', (tester) async {
    final api = FakeOvertimeApi()..rows = [filing()];
    await tester.pumpWidget(host(OvertimeScreen(api: api, baseUrl: 'https://x', today: '2026-11-23', pickers: FakePickers.jpg())));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Report accomplishment'));
    await tester.pumpAndSettle();
    expect(find.text('What did you accomplish on Nov 20, 2026?'), findsOneWidget);
    expect(find.textContaining('(at least 1 · 12 more allowed)', findRichText: true), findsOneWidget);
    // Nothing to send yet.
    expect(tester.widget<FilledButton>(find.byKey(const Key('ot_accomplishment_submit'))).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('ot_accomplishment_note')), '  Reconciled 3 branches  ');
    await tester.pump();
    // Remarks alone are not enough: a picture is needed too (user 2026-11-24).
    expect(tester.widget<FilledButton>(find.byKey(const Key('ot_accomplishment_submit'))).onPressed, isNull);
    await tester.tap(find.text('Add picture'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();
    expect(find.textContaining('(at least 1 · 11 more allowed)', findRichText: true), findsOneWidget);

    await tester.tap(find.byKey(const Key('ot_accomplishment_submit')));
    await tester.pumpAndSettle();
    expect(api.accomplishments, [
      {'date': 51, 'note': 'Reconciled 3 branches', 'photos': 1},
    ]);
    expect(find.text('Accomplishment recorded.'), findsOneWidget);
    expect(api.calls.where((c) => c.startsWith('list')).length, 2);
  });

  testWidgets('a future date cannot be reported yet', (tester) async {
    final api = FakeOvertimeApi()
      ..rows = [
        filing(dates: [
          {'id': 61, 'date': '2026-11-30', 'accomplishment_at': null, 'photos': []},
        ]),
      ];
    await tester.pumpWidget(host(OvertimeScreen(api: api, baseUrl: 'https://x', today: '2026-11-23')));
    await tester.pumpAndSettle();
    expect(find.text('Not yet worked'), findsOneWidget);
    final btn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Report accomplishment'));
    expect(btn.onPressed, isNull);
  });

  testWidgets('pending and holiday filings: no report, the holiday note and form', (tester) async {
    final api = FakeOvertimeApi()
      ..rows = [
        filing(id: 7, status: 'pending', outstanding: 2, dates: [
          {'id': 71, 'date': '2026-11-25', 'photos': []},
        ]),
        filing(id: 8, otType: 'regular_holiday', files: ['/api/uploads/ot/form.jpg'], dates: [
          {'id': 81, 'date': '2026-11-30', 'photos': []},
        ]),
      ];
    await tester.pumpWidget(host(OvertimeScreen(api: api, baseUrl: 'https://x', today: '2026-11-23')));
    await tester.pumpAndSettle();

    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Awaiting approval'), findsOneWidget);
    expect(find.text('Regular holiday'), findsOneWidget);
    expect(find.text('Approved to work'), findsOneWidget);
    expect(find.text('Paid as holiday pay if you worked your last scheduled day before the holiday.'), findsOneWidget);
    expect(find.text('Report accomplishment'), findsNothing);
    expect(find.text('View accomplishment report'), findsNothing);
    expect(find.textContaining('Paid only for the dates'), findsNothing);
  });

  testWidgets('set by my admin: missing form + remarks, then saved through requirements', (tester) async {
    final api = FakeOvertimeApi()
      ..rows = [
        filing(id: 9, otType: 'regular_holiday', assignedBy: 2, purpose: null, dates: [
          {'id': 91, 'date': '2026-11-30', 'photos': []},
        ]),
      ];
    await tester.pumpWidget(host(OvertimeScreen(api: api, baseUrl: 'https://x', today: '2026-11-23', pickers: FakePickers.jpg())));
    await tester.pumpAndSettle();

    expect(find.text('Set by hradmin — already approved. Add the approved form and your remarks.'), findsOneWidget);
    await tester.tap(find.text('Add form and remarks'));
    await tester.pumpAndSettle();
    expect(find.text('Add the approved form and remarks'), findsOneWidget);
    expect(find.textContaining('Holiday work on Nov 30, 2026 — set by hradmin and already approved.'), findsOneWidget);

    // Holiday with no form on file: Save waits for a file AND remarks.
    await tester.enterText(find.byKey(const Key('ot_req_purpose')), 'Inventory count');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byKey(const Key('ot_req_save'))).onPressed, isNull);

    await tester.tap(find.text('Choose files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose a PDF'));
    await tester.pumpAndSettle();
    expect(find.text('form.pdf'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ot_req_save')));
    await tester.pumpAndSettle();
    expect(api.calls, contains('stage application/pdf'));
    expect(api.requirements.single['id'], 9);
    expect(api.requirements.single['purpose'], 'Inventory count');
    expect(api.requirements.single['attachment_url'], startsWith('/api/uploads/overtime/'));
    expect(api.requirements.single.containsKey('more_attachment_urls'), isFalse);
  });

  testWidgets('set by my admin: green when complete, blue while overtime dates are unreported', (tester) async {
    final api = FakeOvertimeApi()
      ..rows = [
        filing(id: 10, otType: 'special_holiday', assignedBy: 2, purpose: 'QA', files: ['/api/uploads/ot/form.jpg'], dates: [
          {'id': 101, 'date': '2026-11-16', 'photos': []},
        ]),
        filing(id: 11, assignedBy: 2, purpose: 'Cabling', dates: [
          {'id': 111, 'date': '2026-11-20', 'accomplishment_at': '2026-11-20 20:00:00', 'photos': []},
          {'id': 112, 'date': '2026-11-21', 'photos': []},
        ]),
      ];
    await tester.pumpWidget(host(OvertimeScreen(api: api, baseUrl: 'https://x', today: '2026-11-23')));
    await tester.pumpAndSettle();
    expect(find.text('Set by hradmin — approved and complete. Nothing more to submit.'), findsOneWidget);
    expect(find.text('Set by hradmin — approved. Report what you accomplished after each date to be paid.'), findsOneWidget);
    expect(find.textContaining('Requirements added'), findsNothing);
  });

  group('file overtime', () {
    Widget form(FakeOvertimeApi api) => MaterialApp(
          home: OvertimeRequestScreen(
            api: api,
            identity: OvertimeIdentity.fromJson({'first_name': 'Daryl', 'last_name': 'Vito', 'department_name': 'Finance'}),
            today: '2026-11-23',
            debounce: Duration.zero,
            pickers: FakePickers.jpg(),
          ),
        );

    testWidgets('identity is shown, required fields are checked, over 3 hours is refused', (tester) async {
      final api = FakeOvertimeApi()
        ..windowJson = {
          'is_holiday': false,
          'hours': 4,
          'start_time': '18:00:00',
          'end_time': '22:00:00',
          'schedule_end': '17:00:00',
          'gap_minutes': 60,
          'earliest_start': '18:00:00',
          'estimated_pay': '450.00',
        };
      await tester.pumpWidget(form(api));
      await tester.pumpAndSettle();

      expect(find.text('Daryl Vito'), findsOneWidget);
      expect(find.text('Finance'), findsOneWidget);
      expect(find.text('Nov 23, 2026'), findsOneWidget);

      await tester.tap(find.byKey(const Key('ot_submit')));
      await tester.pumpAndSettle();
      expect(find.text('Enter how many overtime hours you are requesting.'), findsOneWidget);
      expect(find.text('Choose the date the overtime will be worked.'), findsOneWidget);
      expect(find.text('State why the overtime is needed.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('ot_hours')), '4');
      await tester.pumpAndSettle();
      // The server's window + estimate.
      expect(find.textContaining('6:00 PM – 10:00 PM'), findsOneWidget);
      expect(find.textContaining('₱450.00'), findsOneWidget);
      expect(find.textContaining('the 60-minute break after it is unpaid'), findsOneWidget);

      // Said as it is typed; File stays off until it is 3 or less (user 2026-11-24).
      expect(find.text("Overtime can't be more than 3 hours per date. Enter 3 or less."), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('ot_submit'))).onPressed, isNull);
      expect(api.submitted, isEmpty);
    });

    testWidgets('one date + hours + purpose files the body the web sends', (tester) async {
      final api = FakeOvertimeApi()
        ..windowJson = {'is_holiday': false, 'hours': 2, 'start_time': '18:00:00', 'end_time': '20:00:00', 'estimated_pay': '200'};
      String? popped;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () async {
                popped = await Navigator.of(ctx).push<String>(MaterialPageRoute(
                  builder: (_) => OvertimeRequestScreen(api: api, today: '2026-11-23', debounce: Duration.zero),
                ));
              },
              child: const Text('go'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ot_date_pick')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('ot_hours')), '2');
      await tester.enterText(find.byKey(const Key('ot_purpose')), '  Payroll run  ');
      await tester.pumpAndSettle();
      expect(api.windows.last, '2|2026-11-23');

      await tester.tap(find.byKey(const Key('ot_submit')));
      await tester.pumpAndSettle();
      expect(api.submitted.single, {
        'dates': ['2026-11-23'],
        'ot_hours': 2,
        'purpose': 'Payroll run',
      });
      expect(popped, 'Overtime filed. It now needs your approver.');
    });

    testWidgets('a holiday date switches to holiday work: 8 h locked, form required', (tester) async {
      final api = FakeOvertimeApi()
        ..windowJson = {
          'is_holiday': true,
          'kind_label': 'Regular holiday',
          'holidays': [
            {'date': '2026-11-30', 'title': 'Bonifacio Day'},
          ],
          'max_hours': 8,
          'hours': 8,
          'start_time': '08:00:00',
          'end_time': '17:00:00',
          'estimated_premium': '695.00',
        };
      await tester.pumpWidget(form(api));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ot_date_pick')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ot_holiday_notice')), findsOneWidget);
      expect(find.textContaining('Bonifacio Day'), findsOneWidget);
      expect(find.textContaining('Hours you will work (a full workday)', findRichText: true), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('ot_hours'))).controller!.text, '8');
      expect(find.textContaining('₱695.00'), findsOneWidget);
      expect(find.text('File holiday work'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('ot_purpose')), 'Store inventory');
      await tester.tap(find.byKey(const Key('ot_submit')));
      await tester.pumpAndSettle();
      expect(find.text('Attach the approved holiday work form.'), findsOneWidget);

      await tester.tap(find.text('Choose files'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take a photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add another file'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose a PDF'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ot_submit')));
      await tester.pumpAndSettle();
      final body = api.submitted.single;
      expect(body['ot_hours'], 8);
      expect(body['purpose'], 'Store inventory');
      expect(body['attachment_url'], isNotNull);
      expect((body['more_attachment_urls'] as List).length, 1);
    });

    testWidgets('a 409 clash shows the server field error under the dates', (tester) async {
      final api = FakeOvertimeApi()
        ..windowJson = {'is_holiday': false, 'hours': 1, 'start_time': '18:00:00', 'end_time': '19:00:00'}
        ..submitError = const ApiException(
          status: 409,
          message: 'Conflict',
          fieldErrors: {'dates': 'You already filed overtime for Nov 23, 2026.'},
        );
      await tester.pumpWidget(form(api));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ot_date_pick')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('ot_hours')), '1');
      await tester.enterText(find.byKey(const Key('ot_purpose')), 'x');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ot_submit')));
      await tester.pumpAndSettle();
      expect(find.text('You already filed overtime for Nov 23, 2026.'), findsOneWidget);
    });
  });

  testWidgets('the accomplishment report reads the same document', (tester) async {
    final api = FakeOvertimeApi()
      ..rows = [filing()]
      ..reportJson = {
        'id': 5,
        'status': 'approved',
        'ot_type': 'ordinary',
        'ot_hours': '3.00',
        'start_time': '18:00:00',
        'end_time': '21:00:00',
        'purpose': 'Month-end closing',
        'date_filed': '2026-11-19T02:00:00.000Z',
        'company': {'name': 'PROLSC', 'code': 'PROLSC'},
        'employee': {'name': 'Daryl Vito', 'employee_code': 'PROLSCHO2020003', 'branch': 'Head Office'},
        'approval': {
          'steps': [
            {'level': 1, 'action': 'approved', 'approver': {'username': 'grace', 'role_name': 'Branch Admin'}, 'acted_at': '2026-11-19T05:00:00.000Z'},
          ],
        },
        'dates': filing()['dates'],
        'summary': {'date_count': 2, 'reported_count': 1, 'photo_count': 1},
      };
    await tester.pumpWidget(host(OvertimeScreen(api: api, baseUrl: 'https://x', today: '2026-11-23')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View accomplishment report'));
    await tester.pumpAndSettle();

    expect(find.text('Overtime Accomplishment Report'), findsOneWidget);
    expect(find.text('OT-00005'), findsWidgets);
    expect(find.text('PROLSCHO2020003'), findsOneWidget);
    expect(find.text('grace (Branch Admin)'), findsOneWidget);
    expect(find.text('Not yet reported'), findsOneWidget);
    expect(find.text('1 of 2 dates reported · 1 picture attached'), findsOneWidget);
  });
}
