import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:hris_mobile/core/http/api_exception.dart';
import 'package:hris_mobile/features/attendance/attendance_api.dart';
import 'package:hris_mobile/features/attendance/attendance_controller.dart';
import 'package:hris_mobile/features/attendance/attendance_models.dart';
import 'package:hris_mobile/features/attendance/attendance_screen.dart';
import 'package:hris_mobile/features/attendance/correction_form_screen.dart';
import 'package:provider/provider.dart';

Map<String, dynamic> row(String date, {String dayType = 'worked', String? status = 'present', String? inAt, String? outAt, Map<String, dynamic> extra = const {}}) => {
      'date': date, 'day_type': dayType, 'status': status,
      'clock_in_at': inAt, 'clock_out_at': outAt,
      'worked_minutes': 480, 'late_minutes': 0, 'undertime_minutes': 0,
      'recorded_late_minutes': 0, 'recorded_undertime_minutes': 0,
      'is_late': false, 'is_undertime': false, 'is_half_day': false, 'is_on_leave': false,
      'leave_type_name': null, 'leave_day_part': null, 'holiday_title': null, 'holiday_type': null,
      'shift_start_time': '08:00:00', 'shift_end_time': '17:00:00', 'capture_method': null,
      // What the server also sends and the app must never show:
      'location_in_lat': 14.5513, 'location_in_lng': 121.0175, 'location_in_address': 'Makati',
      'worksite': {'lat': 14.55, 'lng': 121.01},
      ...extra,
    };

class FakeAttendanceApi implements AttendanceApi {
  final Map<String, List<Map<String, dynamic>>> byMonth;
  final calls = <String>[];
  Object? error;
  FakeAttendanceApi(this.byMonth);

  @override
  Future<List<DtrDay>> month({required int year, required int month, required String upToDate}) async {
    final key = '$year-${month.toString().padLeft(2, '0')}';
    calls.add('$key<=$upToDate');
    if (error != null) throw error!;
    return (byMonth[key] ?? const []).map(DtrDay.fromJson).toList();
  }

  Map<String, dynamic> summaryJson = const {'totals': {'records': 0}, 'items': []};
  List<Map<String, dynamic>> correctionRows = const [];
  final staged = <String>[];
  final submitted = <Map<String, dynamic>>[];

  @override
  Future<AttendanceSummary> summary({String? dateFrom, String? dateTo}) async {
    calls.add('summary ${dateFrom ?? ''}..${dateTo ?? ''}');
    return AttendanceSummary.fromJson(summaryJson);
  }

  @override
  Future<List<CorrectionRequest>> corrections() async => correctionRows.map(CorrectionRequest.fromJson).toList();

  Map<String, dynamic> biometricJson = const {'enrolled': true, 'model_version': 'arcface-v1', 'consent_given': true};
  @override
  Future<BiometricStatus> biometric() async => BiometricStatus.fromJson(biometricJson);

  @override
  Future<String> stageProof({required Uint8List bytes, required String mimeType, required String name}) async {
    staged.add('$mimeType $name ${bytes.length}');
    return '/uploads/attendance-requests/proof.jpg';
  }

  @override
  Future<void> submitCorrection(Map<String, dynamic> payload) async => submitted.add(payload);
}

void main() {
  test('DtrDay parses the DTR fields and carries NO location', () {
    final d = DtrDay.fromJson(row('2026-09-11', status: 'late', inAt: '2026-09-11T06:36:24.000Z', outAt: '2026-09-11T06:36:53.000Z', extra: {'is_late': true, 'recorded_late_minutes': 336, 'capture_method': 'mobile'}));
    expect(d.date, '2026-09-11');
    expect(d.year, 2026);
    expect(d.month, 9);
    expect(d.dayType, 'worked');
    expect(d.isLate, isTrue);
    expect(d.lateMinutes, 336);
    expect(d.clockInAt, DateTime.utc(2026, 9, 11, 6, 36, 24));
    expect(d.captureMethod, 'mobile');
    expect(d.workedLabel, '8h 00m');
    // The model has no way to hold a coordinate.
    expect(d.toString().contains('14.55'), isFalse);
    expect(d.correctedLabel, isNull);
  });

  test('a corrected time is marked, like the web DTR (2026-11-12)', () {
    DtrDay day(Map<String, dynamic> extra, {String? outAt = '2026-11-12T09:00:00.000Z'}) =>
        DtrDay.fromJson(row('2026-11-12', status: 'late', inAt: '2026-11-12T06:50:00.000Z', outAt: outAt, extra: extra));
    expect(day({'clock_in_corrected': 1}).correctedLabel, 'In corrected');
    expect(day({'clock_out_corrected': 1}).correctedLabel, 'Out corrected');
    expect(day({'clock_in_corrected': 1, 'clock_out_corrected': 1}).correctedLabel, 'In + out corrected');
    // No clock-out yet: nothing to mark on that side.
    expect(day({'clock_out_corrected': 1}, outAt: null).correctedLabel, isNull);
  });

  test('the controller loads the current Manila month up to today, then walks back', () async {
    final api = FakeAttendanceApi({
      '2026-09': [row('2026-09-01'), row('2026-09-11')],
      '2026-08': [row('2026-08-31', dayType: 'rest_day', status: null)],
    });
    // 2026-09-11 16:30 UTC is already 2026-09-12 00:30 in Manila.
    final c = AttendanceController(api: api, nowUtc: () => DateTime.utc(2026, 9, 11, 16, 30));
    expect(c.today, '2026-09-12');
    await c.loadCurrent();
    expect(api.calls, ['2026-09<=2026-09-12']);
    expect(c.months.single.days.map((d) => d.date), ['2026-09-11', '2026-09-01']); // newest first
    await c.loadPrevious();
    expect(api.calls.last, '2026-08<=2026-09-12');
    expect(c.months.length, 2);
    expect(c.months.last.count('rest_day'), 1);
  });

  test('a failed load keeps what was loaded and reports the error', () async {
    final api = FakeAttendanceApi({'2026-09': [row('2026-09-11')]});
    final c = AttendanceController(api: api, nowUtc: () => DateTime.utc(2026, 9, 11, 3));
    await c.loadCurrent();
    api.error = const ApiException(status: 0, code: 'NETWORK_ERROR', message: 'Cannot reach the server.');
    await c.loadPrevious();
    expect(c.months.length, 1);
    expect(c.error, contains('Cannot reach'));
  });

  testWidgets('Records is the web page on a phone: face card, the DTR table with its eight columns, never a coordinate', (tester) async {
    final api = FakeAttendanceApi({
      '2026-09': [
        row('2026-09-11', status: 'late', inAt: '2026-09-11T00:36:24.000Z', outAt: '2026-09-11T09:00:00.000Z',
            extra: {'is_late': true, 'recorded_late_minutes': 36, 'late_reason': 'Flat tire', 'capture_method': 'mobile'}),
        row('2026-09-10', dayType: 'absent', status: 'absent', extra: {'worked_minutes': 0}),
        row('2026-09-06', dayType: 'rest_day', status: null, extra: {'worked_minutes': 0}),
        row('2026-09-04', dayType: 'on_leave', status: null,
            extra: {'worked_minutes': 0, 'is_on_leave': true, 'leave_type_name': 'Sick Leave', 'leave_day_part': 'am_half'}),
        row('2026-09-01', dayType: 'holiday', status: null, extra: {'worked_minutes': 0, 'holiday_title': 'National Heroes Day'}),
      ],
    });
    final c = AttendanceController(api: api, nowUtc: () => DateTime.utc(2026, 9, 11, 3));
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider<AttendanceController>.value(value: c, child: const Scaffold(body: AttendanceScreen())),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Your daily time record and corrections.'), findsOneWidget);
    expect(find.text('Face enrollment'), findsOneWidget);
    expect(find.text('Enrolled'), findsOneWidget);
    expect(find.text('Daily time record'), findsOneWidget);
    for (final h in ['DATE', 'CLOCK IN', 'CLOCK OUT', 'WORKED', 'LATE', 'UNDERTIME', 'STATUS', 'METHOD']) {
      expect(find.text(h), findsOneWidget, reason: h);
    }
    expect(find.text('8:36 AM'), findsOneWidget);
    expect(find.text('5:00 PM'), findsOneWidget);
    expect(find.text('36m'), findsOneWidget);
    expect(find.text('Flat tire'), findsOneWidget); // my reason, under the late time
    expect(find.text('Late'), findsOneWidget);
    expect(find.text('Mobile app'), findsNWidgets(2)); // In + Out
    expect(find.text('Absent'), findsOneWidget);
    expect(find.text('Rest day'), findsOneWidget);
    expect(find.text('On Leave · Sick Leave (AM)'), findsOneWidget);
    expect(find.text('National Heroes Day'), findsOneWidget);
    expect(find.textContaining('14.55'), findsNothing);
    expect(find.textContaining('Makati'), findsNothing);
    expect(find.text('Load previous month'), findsOneWidget);
  });

  testWidgets('a day the DTR import replaced reads Import and opens the original web clock (2026-11-24)', (tester) async {
    final api = FakeAttendanceApi({
      '2026-09': [
        row('2026-09-11', status: 'late', inAt: '2026-09-11T00:24:00.000Z', outAt: '2026-09-11T09:01:00.000Z', extra: {
          'capture_method': 'manual', 'clock_in_method': 'manual', 'clock_out_method': 'manual',
          'clock_in_corrected': 1, 'clock_out_corrected': 1, 'corrected_from_import': 1, 'correction_source': 'admin',
          'clock_in_original_at': '2026-09-11T00:24:48.000Z', 'clock_in_original_method': 'web',
          'clock_out_original_at': '2026-09-11T09:00:58.000Z', 'clock_out_original_method': 'web',
        }),
        row('2026-09-10', status: 'present', inAt: '2026-09-10T00:00:00.000Z', outAt: '2026-09-10T09:00:00.000Z',
            extra: {'capture_method': 'web', 'clock_in_corrected': 1, 'correction_source': 'admin'}),
      ],
    });
    final c = AttendanceController(api: api, nowUtc: () => DateTime.utc(2026, 9, 11, 3));
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider<AttendanceController>.value(value: c, child: const Scaffold(body: AttendanceScreen())),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Import'), findsNWidgets(2)); // In + Out of the imported day
    expect(find.text('Corrected'), findsOneWidget); // an admin's own edit stays Corrected
    expect(find.text('Web clock'), findsOneWidget); // its untouched clock-out

    await tester.ensureVisible(find.byKey(const Key('dtr_trail_2026-09-11_in')));
    await tester.tap(find.byKey(const Key('dtr_trail_2026-09-11_in')));
    await tester.pumpAndSettle();
    expect(find.text('Imported time'), findsOneWidget);
    expect(find.text('8:24 AM (Web clock)'), findsOneWidget);
    expect(find.text('5:00 PM (Web clock)'), findsOneWidget);
    expect(find.text('Source: Imported DTR file (Excel)'), findsOneWidget);
  });

  test('summary periods are Manila days, as the web periodRange', () {
    // 2026-10-27 18:00 UTC is already Oct 28 in Manila.
    final c = AttendanceController(api: FakeAttendanceApi({}), nowUtc: () => DateTime.utc(2026, 10, 27, 18));
    expect(c.rangeOf(SummaryPeriod.thisMonth), ('2026-10-01', '2026-10-28'));
    expect(c.rangeOf(SummaryPeriod.lastMonth), ('2026-09-01', '2026-09-30'));
    expect(c.rangeOf(SummaryPeriod.last3Months), ('2026-08-01', '2026-10-28'));
    expect(c.rangeOf(SummaryPeriod.thisYear), ('2026-01-01', '2026-10-28'));
    expect(c.rangeOf(SummaryPeriod.all), ('', ''));
  });

  test('summary totals parse MySQL string sums; a null average stays null', () {
    final s = AttendanceSummary.fromJson({
      'totals': {
        'records': '22', 'present_days': '2', 'late_days': '4', 'late_minutes': '1591', 'absent_days': '16',
        'worked_minutes': '2176', 'avg_worked_minutes': 363, 'first_date': '2026-10-01', 'last_date': '2026-10-26T00:00:00.000Z',
      },
      'items': [
        {'period': '2026-10', 'records': 22, 'avg_worked_minutes': null},
      ],
    });
    expect(s.totals.records, 22);
    expect(s.totals.lateMinutes, 1591);
    expect(s.totals.avgWorkedMinutes, 363);
    expect(s.totals.lastDate, '2026-10-26');
    expect(s.months.single.monthLabel, 'Oct 2026');
    expect(s.months.single.avgWorkedMinutes, isNull);
  });

  test('a Manila clock time is sent in UTC, as the web does', () {
    expect(manilaToUtcText('2026-10-23', const TimeOfDay(hour: 18, minute: 5)), '2026-10-23 10:05');
    // Before 8 AM Manila is still the previous UTC day.
    expect(manilaToUtcText('2026-10-23', const TimeOfDay(hour: 7, minute: 30)), '2026-10-22 23:30');
  });

  test('the proof type comes from the bytes, never the name', () {
    expect(sniffImageType(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])), 'image/jpeg');
    expect(sniffImageType(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D])), 'image/png');
    expect(sniffImageType(Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D])), isNull); // a PDF
  });

  testWidgets('My Attendance has Records | Summary and File a correction; Summary shows the tiles and months', (tester) async {
    final api = FakeAttendanceApi({'2026-10': [row('2026-10-23')]})
      ..correctionRows = [
        {
          'id': 1, 'date': '2026-10-19', 'requested_clock_in': null, 'requested_clock_out': '2026-10-19 10:00:00',
          'status': 'pending', 'reason': 'Terminal was down',
        },
      ]
      ..summaryJson = {
        'totals': {
          'records': 22, 'present_days': 2, 'late_days': 4, 'late_minutes': 1591, 'absent_days': 16,
          'worked_minutes': 2176, 'avg_worked_minutes': 363, 'undertime_incidents': 2, 'undertime_minutes': 108,
          'missing_clock_out': 9, 'open_days': 4, 'face_days': 0, 'flagged_days': 1, 'half_days': 0,
          'first_date': '2026-10-01', 'last_date': '2026-10-26',
        },
        'items': [
          {'period': '2026-10', 'records': 22, 'present_days': 2, 'late_days': 4, 'absent_days': 16, 'worked_minutes': 2176, 'avg_worked_minutes': 363},
        ],
      };
    final c = AttendanceController(api: api, nowUtc: () => DateTime.utc(2026, 10, 27, 3));
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider<AttendanceController>.value(value: c, child: const Scaffold(body: AttendanceScreen())),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Records'), findsOneWidget);
    expect(find.text('File a correction'), findsOneWidget);
    // The page scrolls down; the tables scroll sideways — scroll the page.
    final page = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;
    await tester.scrollUntilVisible(find.text('Terminal was down'), 200, scrollable: page);
    expect(find.text('My correction requests'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('REQUESTED OUT'), findsOneWidget);
    expect(find.textContaining('6:00 PM'), findsOneWidget);

    await tester.tap(find.text('Summary'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('summary 2026-01-01..2026-10-27'));
    expect(find.text('Days recorded'), findsOneWidget);
    expect(find.text('16'), findsOneWidget);
    expect(find.text('26h 31m total'), findsOneWidget);
    expect(find.text('6h 03m avg / complete day'), findsOneWidget);
    expect(find.text('Half-days'), findsNothing); // hidden: none
    await tester.scrollUntilVisible(find.text('OCT 2026'), 200);
    expect(find.text('Flagged location'), findsOneWidget); // shown: there is one
    expect(find.text('22 days · 2 present · 4 late · 16 absent'), findsOneWidget);
  });

  testWidgets('the correction form refuses an incomplete request, then stages the photo and files it', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final api = FakeAttendanceApi({});
    final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
    bool? popped;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () async {
              popped = await Navigator.of(ctx).push<bool>(MaterialPageRoute(
                builder: (_) => CorrectionFormScreen(
                  api: api,
                  today: '2026-10-27',
                  initialDate: '2026-10-23',
                  picker: (ImageSource _) async => PickedProof(bytes: jpeg, mimeType: 'image/jpeg', name: 'cctv.jpg'),
                ),
              ));
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Oct 23, 2026'), findsOneWidget);
    await tester.tap(find.text('Submit correction'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a corrected clock-in and/or clock-out.'), findsOneWidget);
    expect(find.text('Attach a photo proving you were at the office.'), findsOneWidget);
    expect(find.text('Explain why you were not able to clock out.'), findsOneWidget);
    expect(api.submitted, isEmpty);

    // Clock-out through the time picker, accepting its 5:00 PM default.
    await tester.ensureVisible(find.text('Corrected clock-out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Corrected clock-out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Choose photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();
    expect(find.text('cctv.jpg'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'The terminal was down when I left.');
    await tester.tap(find.text('Submit correction'));
    await tester.pumpAndSettle();

    expect(api.staged, ['image/jpeg cctv.jpg 7']);
    expect(api.submitted.single, {
      'date': '2026-10-23',
      'reason': 'The terminal was down when I left.',
      'proof_photo_url': '/uploads/attendance-requests/proof.jpg',
      'requested_clock_out': '2026-10-23 09:00', // 5:00 PM Manila
    });
    expect(popped, isTrue);
  });
}
