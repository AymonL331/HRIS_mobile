import '../../core/time/duration_label.dart';
import '../../core/time/manila_time.dart';

int _int(Object? v) => v == null ? 0 : (v is int ? v : int.tryParse('$v') ?? 0);
bool _flag(Object? v) => v == true || v == 1 || v == '1';

/// One calendar day of the employee's DTR, from `GET /api/me/attendance/calendar`.
///
/// DELIBERATELY has no location or worksite fields: the server sends them, the
/// parser ignores them, so coordinates cannot reach this screen by accident.
/// Location is admin-DTR-only for employees, same as the web app.
class DtrDay {
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
  final String? leaveDayPart; // full | am | pm
  final String? holidayTitle;
  final String? holidayType;
  final String? shiftStart;
  final String? shiftEnd;
  final String? captureMethod;

  const DtrDay({
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
    required this.holidayType,
    required this.shiftStart,
    required this.shiftEnd,
    required this.captureMethod,
  });

  factory DtrDay.fromJson(Map<String, dynamic> j) => DtrDay(
        date: '${j['date'] ?? ''}'.substring(0, '${j['date'] ?? ''}'.length.clamp(0, 10)),
        dayType: (j['day_type'] ?? 'no_record') as String,
        status: j['status'] as String?,
        clockInAt: ManilaTime.parseUtc(j['clock_in_at'] as String?),
        clockOutAt: ManilaTime.parseUtc(j['clock_out_at'] as String?),
        workedMinutes: _int(j['worked_minutes']),
        lateMinutes: _int(j['recorded_late_minutes'] ?? j['late_minutes']),
        undertimeMinutes: _int(j['recorded_undertime_minutes'] ?? j['undertime_minutes']),
        isLate: _flag(j['is_late']),
        isUndertime: _flag(j['is_undertime']),
        isHalfDay: _flag(j['is_half_day']),
        isOnLeave: _flag(j['is_on_leave']),
        leaveTypeName: j['leave_type_name'] as String?,
        leaveDayPart: j['leave_day_part'] as String?,
        holidayTitle: j['holiday_title'] as String?,
        holidayType: j['holiday_type'] as String?,
        shiftStart: j['shift_start_time'] as String?,
        shiftEnd: j['shift_end_time'] as String?,
        captureMethod: j['capture_method'] as String?,
      );

  int get year => int.parse(date.substring(0, 4));
  int get month => int.parse(date.substring(5, 7));

  String get workedLabel => workedMinutes <= 0 ? '' : hoursMinutes(workedMinutes);
}

/// A month of days plus the counts the header shows.
class DtrMonth {
  final int year;
  final int month;
  final List<DtrDay> days; // newest first

  const DtrMonth({required this.year, required this.month, required this.days});

  int count(String dayType) => days.where((d) => d.dayType == dayType).length;
  int get lateCount => days.where((d) => d.isLate).length;
}
