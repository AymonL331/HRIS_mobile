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

/// The figures of `GET /api/me/attendance/summary` — the headline totals for the
/// period, and (with [period] set) one month of the breakdown. The SAME fields
/// the web's summary tiles and month table read; sums arrive as strings from
/// MySQL, so every count goes through [_int].
class AttendanceTotals {
  final String? period; // 'YYYY-MM' on a breakdown row, null on the totals
  final int records;
  final int presentDays;
  final int obDays;
  final int lateDays;
  final int lateMinutes;
  final int absentDays;
  final int workedMinutes;
  final int? avgWorkedMinutes; // null = no complete day to average
  final int undertimeIncidents;
  final int undertimeMinutes;
  final int halfDays;
  final int missingClockOut;
  final int openDays;
  final int faceDays;
  final int flaggedDays;
  final String? firstDate;
  final String? lastDate;

  const AttendanceTotals({
    this.period,
    required this.records,
    required this.presentDays,
    required this.obDays,
    required this.lateDays,
    required this.lateMinutes,
    required this.absentDays,
    required this.workedMinutes,
    required this.avgWorkedMinutes,
    required this.undertimeIncidents,
    required this.undertimeMinutes,
    required this.halfDays,
    required this.missingClockOut,
    required this.openDays,
    required this.faceDays,
    required this.flaggedDays,
    this.firstDate,
    this.lastDate,
  });

  static String? _date(Object? v) {
    final s = v?.toString();
    return s == null || s.length < 10 ? null : s.substring(0, 10);
  }

  factory AttendanceTotals.fromJson(Map<String, dynamic> j) => AttendanceTotals(
        period: j['period']?.toString(),
        records: _int(j['records']),
        presentDays: _int(j['present_days']),
        obDays: _int(j['ob_days']),
        lateDays: _int(j['late_days']),
        lateMinutes: _int(j['late_minutes']),
        absentDays: _int(j['absent_days']),
        workedMinutes: _int(j['worked_minutes']),
        avgWorkedMinutes: j['avg_worked_minutes'] == null ? null : _int(j['avg_worked_minutes']),
        undertimeIncidents: _int(j['undertime_incidents']),
        undertimeMinutes: _int(j['undertime_minutes']),
        halfDays: _int(j['half_days']),
        missingClockOut: _int(j['missing_clock_out']),
        openDays: _int(j['open_days']),
        faceDays: _int(j['face_days']),
        flaggedDays: _int(j['flagged_days']),
        firstDate: _date(j['first_date']),
        lastDate: _date(j['last_date']),
      );

  /// "Oct 2026" for a breakdown row.
  String get monthLabel {
    final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(period ?? '');
    if (m == null) return period ?? '—';
    return ManilaTime.shortMonthLabel(int.parse(m[1]!), int.parse(m[2]!));
  }
}

/// The whole summary answer: the totals and the months behind them, newest first.
class AttendanceSummary {
  final AttendanceTotals totals;
  final List<AttendanceTotals> months;

  const AttendanceSummary({required this.totals, required this.months});

  factory AttendanceSummary.fromJson(Map<String, dynamic> j) => AttendanceSummary(
        totals: AttendanceTotals.fromJson((j['totals'] as Map<String, dynamic>?) ?? const {}),
        months: ((j['items'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AttendanceTotals.fromJson)
            .toList(),
      );
}

/// One of MY DTR correction requests (`GET /api/me/correction-requests`) — the
/// web's "My correction requests" table row.
class CorrectionRequest {
  final int id;
  final String date;
  final DateTime? requestedClockIn;
  final DateTime? requestedClockOut;
  final String status; // pending | approved | rejected | cancelled
  final String? reason;
  final String? proofPhotoUrl;

  const CorrectionRequest({
    required this.id,
    required this.date,
    required this.requestedClockIn,
    required this.requestedClockOut,
    required this.status,
    required this.reason,
    required this.proofPhotoUrl,
  });

  factory CorrectionRequest.fromJson(Map<String, dynamic> j) => CorrectionRequest(
        id: _int(j['id']),
        date: '${j['date'] ?? ''}'.substring(0, '${j['date'] ?? ''}'.length.clamp(0, 10)),
        requestedClockIn: ManilaTime.parseUtc(j['requested_clock_in']?.toString()),
        requestedClockOut: ManilaTime.parseUtc(j['requested_clock_out']?.toString()),
        status: (j['status'] ?? 'pending').toString(),
        reason: j['reason'] as String?,
        proofPhotoUrl: j['proof_photo_url'] as String?,
      );
}
