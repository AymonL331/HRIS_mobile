import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/http/api_exception.dart';
import 'package:hris_mobile/features/attendance/attendance_api.dart';
import 'package:hris_mobile/features/attendance/attendance_controller.dart';
import 'package:hris_mobile/features/attendance/attendance_models.dart';
import 'package:hris_mobile/features/attendance/attendance_screen.dart';
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

  testWidgets('the screen renders the month header, badges, chips and times, and never a coordinate', (tester) async {
    final api = FakeAttendanceApi({
      '2026-09': [
        row('2026-09-11', status: 'late', inAt: '2026-09-11T00:36:24.000Z', outAt: '2026-09-11T09:00:00.000Z', extra: {'is_late': true, 'recorded_late_minutes': 36, 'capture_method': 'mobile'}),
        row('2026-09-10', dayType: 'absent', status: 'absent', extra: {'worked_minutes': 0, 'capture_method': 'system'}),
        row('2026-09-06', dayType: 'rest_day', status: null, extra: {'worked_minutes': 0}),
        row('2026-09-04', dayType: 'on_leave', status: null, extra: {'worked_minutes': 0, 'is_on_leave': true, 'leave_type_name': 'Sick Leave', 'leave_day_part': 'am'}),
        row('2026-09-01', dayType: 'holiday', status: null, extra: {'worked_minutes': 0, 'holiday_title': 'National Heroes Day'}),
      ],
    });
    final c = AttendanceController(api: api, nowUtc: () => DateTime.utc(2026, 9, 11, 3));
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider<AttendanceController>.value(value: c, child: const Scaffold(body: AttendanceScreen())),
    ));
    await tester.pumpAndSettle();

    expect(find.text('September 2026'), findsOneWidget);
    expect(find.text('1 worked · 1 late · 1 absent · 1 on leave'), findsOneWidget);
    expect(find.text('Late'), findsOneWidget);
    expect(find.text('Late 36 min'), findsOneWidget);
    expect(find.text('8:36 AM  →  5:00 PM'), findsOneWidget);
    expect(find.text('Mobile app'), findsOneWidget);
    expect(find.text('Absent'), findsOneWidget);
    expect(find.text('Rest day'), findsOneWidget);
    expect(find.text('Sick Leave (AM)'), findsOneWidget);
    expect(find.text('National Heroes Day'), findsOneWidget);
    expect(find.textContaining('14.55'), findsNothing);
    expect(find.textContaining('Makati'), findsNothing);
    expect(find.text('Load previous month'), findsOneWidget);
  });
}
