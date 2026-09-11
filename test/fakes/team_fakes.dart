import 'package:hris_mobile/features/attendance/team_api.dart';
import 'package:hris_mobile/features/attendance/team_models.dart';

/// One employee's calendar cell as `GET /api/attendance/calendar` sends it.
Map<String, dynamic> cell(
  int employeeId,
  String name, {
  String code = 'EMP',
  String date = '2026-09-11',
  String dayType = 'worked',
  String? status = 'present',
  String? inAt,
  String? outAt,
  Map<String, dynamic> extra = const {},
}) =>
    {
      'id': dayType == 'worked' || dayType == 'absent' ? employeeId * 10 : null,
      'employee_id': employeeId,
      'employee_name': name,
      'employee_code': code,
      'date': date,
      'day_type': dayType,
      'status': status,
      'clock_in_at': inAt,
      'clock_out_at': outAt,
      'worked_minutes': inAt != null && outAt != null ? 480 : 0,
      'late_minutes': 0,
      'undertime_minutes': 0,
      'is_late': false,
      'is_undertime': false,
      'is_half_day': false,
      'is_on_leave': dayType == 'on_leave',
      'leave_type_name': null,
      'leave_day_part': null,
      'holiday_title': null,
      'holiday_type': null,
      'capture_method': inAt == null ? null : 'manual',
      'clock_in_method': inAt == null ? null : 'manual',
      'clock_out_method': outAt == null ? null : 'manual',
      'location_in_flagged': 0,
      'location_out_flagged': 0,
      'location_flag_reason': null,
      'location_in_address': null,
      'location_out_address': null,
      // Sent by the server, never held by the model:
      'location_in_lat': 14.5513714,
      'location_in_lng': 121.0175541,
      'worksite': null,
      ...extra,
    };

Map<String, dynamic> pageJson(List<Map<String, dynamic>> items, {int page = 1, int totalPages = 1, int? total}) => {
      'items': items,
      'pagination': {'page': page, 'limit': 100, 'total': total ?? items.length, 'totalPages': totalPages},
    };

/// A scripted team DTR: `byDate[date]` is the page-1 payload; `pages[(date, page)]`
/// overrides a specific page. Records every call as "date|search|page".
class FakeTeamApi implements TeamAttendanceApi {
  final Map<String, Map<String, dynamic>> byDate;
  final Map<(String, int), Map<String, dynamic>> pages;
  final calls = <String>[];
  Object? error;

  FakeTeamApi(this.byDate, {this.pages = const {}});

  @override
  Future<TeamDayPage> day({required String date, String search = '', int page = 1}) async {
    calls.add('$date|$search|$page');
    if (error != null) throw error!;
    final raw = pages[(date, page)] ?? byDate[date] ?? pageJson(const []);
    if (search.trim().isEmpty) return TeamDayPage.fromJson(date, raw);
    // The server matches name or code; the fake does the same on the page it holds.
    final q = search.trim().toLowerCase();
    final items = ((raw['items'] as List).cast<Map<String, dynamic>>())
        .where((i) => '${i['employee_name']}'.toLowerCase().contains(q) || '${i['employee_code']}'.toLowerCase().contains(q))
        .toList();
    return TeamDayPage.fromJson(date, pageJson(items));
  }
}
