import '../../core/time/manila_time.dart';

int _int(Object? v) => v == null ? 0 : (v is int ? v : int.tryParse('$v') ?? 0);
int? _intOrNull(Object? v) => v == null ? null : (v is int ? v : int.tryParse('$v'));
bool _flag(Object? v) => v == true || v == 1 || v == '1';
bool? _flagOrNull(Object? v) => v == null ? null : _flag(v);

/// One employee's day on the team DTR (`GET /api/attendance/calendar`, one
/// cell per employee for the chosen date).
///
/// Carries the verdicts a supervisor needs — who is in, late, absent, out of
/// range — plus the place LABELS the server resolved at punch time. It has no
/// field for a raw coordinate on purpose: the phone shows where a punch was
/// made in words, never as a pin to copy.
class TeamDay {
  final int employeeId;
  final String employeeName;
  final String? employeeCode;
  final String date; // YYYY-MM-DD, tenant-local
  final String dayType; // worked | absent | on_leave | holiday | rest_day | no_record
  final String? status; // present | late | absent | official_business | null
  final DateTime? clockInAt;
  final DateTime? clockOutAt;
  final int workedMinutes;
  final int lateMinutes;
  final int undertimeMinutes;
  final bool isLate;
  final bool isUndertime;
  final bool isHalfDay;
  final bool isOnLeave;
  final String? leaveTypeName;
  final String? leaveDayPart;
  final String? holidayTitle;
  final String? captureMethod;
  final String? clockInMethod;
  final String? clockOutMethod;
  final bool? inWithin; // null = no geotag on the IN punch
  final bool? outWithin;
  final int? inDistanceM;
  final int? outDistanceM;
  final bool locationFlagged;
  final String? locationFlagReason;
  final String? inAddress;
  final String? outAddress;

  const TeamDay({
    required this.employeeId,
    required this.employeeName,
    required this.employeeCode,
    required this.date,
    required this.dayType,
    required this.status,
    required this.clockInAt,
    required this.clockOutAt,
    required this.workedMinutes,
    required this.lateMinutes,
    required this.undertimeMinutes,
    required this.isLate,
    required this.isUndertime,
    required this.isHalfDay,
    required this.isOnLeave,
    required this.leaveTypeName,
    required this.leaveDayPart,
    required this.holidayTitle,
    required this.captureMethod,
    required this.clockInMethod,
    required this.clockOutMethod,
    required this.inWithin,
    required this.outWithin,
    required this.inDistanceM,
    required this.outDistanceM,
    required this.locationFlagged,
    required this.locationFlagReason,
    required this.inAddress,
    required this.outAddress,
  });

  factory TeamDay.fromJson(Map<String, dynamic> j) {
    final worksite = j['worksite'];
    final w = worksite is Map<String, dynamic> ? worksite : const <String, dynamic>{};
    final rawDate = '${j['date'] ?? ''}';
    final name = '${j['employee_name'] ?? ''}'.trim();
    return TeamDay(
      employeeId: _int(j['employee_id']),
      employeeName: name.isEmpty ? 'Employee #${_int(j['employee_id'])}' : name,
      employeeCode: j['employee_code'] as String?,
      date: rawDate.substring(0, rawDate.length.clamp(0, 10)),
      dayType: (j['day_type'] ?? 'no_record') as String,
      status: j['status'] as String?,
      clockInAt: ManilaTime.parseUtc(j['clock_in_at'] as String?),
      clockOutAt: ManilaTime.parseUtc(j['clock_out_at'] as String?),
      workedMinutes: _int(j['worked_minutes']),
      lateMinutes: _int(j['late_minutes']),
      undertimeMinutes: _int(j['undertime_minutes']),
      isLate: _flag(j['is_late']),
      isUndertime: _flag(j['is_undertime']),
      isHalfDay: _flag(j['is_half_day']),
      isOnLeave: _flag(j['is_on_leave']),
      leaveTypeName: j['leave_type_name'] as String?,
      leaveDayPart: j['leave_day_part'] as String?,
      holidayTitle: j['holiday_title'] as String?,
      captureMethod: j['capture_method'] as String?,
      clockInMethod: j['clock_in_method'] as String?,
      clockOutMethod: j['clock_out_method'] as String?,
      inWithin: _flagOrNull(w['in_within']),
      outWithin: _flagOrNull(w['out_within']),
      inDistanceM: _intOrNull(w['in_distance_m']),
      outDistanceM: _intOrNull(w['out_distance_m']),
      locationFlagged: _flag(j['location_in_flagged']) || _flag(j['location_out_flagged']),
      locationFlagReason: j['location_flag_reason'] as String?,
      inAddress: j['location_in_address'] as String?,
      outAddress: j['location_out_address'] as String?,
    );
  }

  bool get hasPunch => clockInAt != null || clockOutAt != null;
  bool get isMobilePunch => captureMethod == 'mobile' || clockInMethod == 'mobile' || clockOutMethod == 'mobile';
  bool get outOfRange => inWithin == false || outWithin == false;

  String get workedLabel {
    if (workedMinutes <= 0) return '';
    final h = workedMinutes ~/ 60;
    final m = workedMinutes % 60;
    return h > 0 ? '${h}h ${m.toString().padLeft(2, '0')}m' : '${m}m';
  }
}

/// One page of the team DTR for a date, plus what the header counts.
class TeamDayPage {
  final String date;
  final List<TeamDay> items;
  final int page;
  final int totalPages;
  final int total;

  const TeamDayPage({
    required this.date,
    required this.items,
    required this.page,
    required this.totalPages,
    required this.total,
  });

  factory TeamDayPage.fromJson(String date, Map<String, dynamic> j) {
    final items = ((j['items'] as List?) ?? const []).whereType<Map<String, dynamic>>().map(TeamDay.fromJson).toList();
    final p = j['pagination'];
    final pg = p is Map<String, dynamic> ? p : const <String, dynamic>{};
    return TeamDayPage(
      date: date,
      items: items,
      page: _int(pg['page']) == 0 ? 1 : _int(pg['page']),
      totalPages: _int(pg['totalPages']) == 0 ? 1 : _int(pg['totalPages']),
      total: _int(pg['total']),
    );
  }

  bool get hasMore => page < totalPages;
}
