import 'package:intl/intl.dart';

import '../../core/time/manila_time.dart';
import '../../shared/widgets/status_badge.dart';

// OVERTIME & HOLIDAY WORK (web pages/employee/MyOvertimePage.jsx) — the shapes of
// /api/me/overtime-requests, /overtime-window and /overtime-requests/:id/report,
// and the web's constants/overtimeEnums.js labels, tones and helpers, word for word.

/// overtime_requests.status → OT_STATUS_LABELS.
const otStatusLabels = {
  'pending': 'Pending',
  'approved': 'Approved',
  'rejected': 'Rejected',
  'cancelled': 'Cancelled',
};

/// OT_STATUS_TONE.
StatusTone otStatusTone(String status) => switch (status) {
      'pending' => StatusTone.warning,
      'approved' => StatusTone.success,
      'rejected' => StatusTone.danger,
      _ => StatusTone.neutral,
    };

/// OT_TYPE_LABELS — the Labor Code day classifications.
const otTypeLabels = {
  'ordinary': 'Ordinary day',
  'rest_day': 'Rest day',
  'special_holiday': 'Special holiday',
  'regular_holiday': 'Regular holiday',
  'special_holiday_rest_day': 'Special holiday on a rest day',
  'regular_holiday_rest_day': 'Regular holiday on a rest day',
  'double_holiday': 'Double holiday',
  'double_holiday_rest_day': 'Double holiday on a rest day',
};

/// HOLIDAY_WORK_TYPES: a filing on one of these IS the request to work the holiday.
const holidayWorkTypes = ['regular_holiday', 'special_holiday', 'double_holiday'];
bool isHolidayWork(String? otType) => holidayWorkTypes.contains(otType);

/// OT_CAN_REPORT: only an APPROVED filing can take an accomplishment.
bool otCanReport(String status) => status == 'approved';

/// Ordinary overtime is at most 3 hours per date (server MAX_OVERTIME_HOURS).
const maxOvertimeHours = 3;

/// Up to 5 files on a filing (migration 124), 10 MB each (HolidayWorkFormField).
const maxFormFiles = 5;
const maxFormFileMb = 10;

/// Up to 12 accomplishment pictures (validators/overtime MAX_ACCOMPLISHMENT_PHOTOS).
const maxAccomplishmentPhotos = 12;

/// 'HH:MM:SS' → "7:00 PM"; '' when missing (formatTimeOfDay).
String formatTimeOfDay(Object? value) {
  final m = RegExp(r'^(\d{2}):(\d{2})').firstMatch('${value ?? ''}');
  if (m == null) return '';
  final h = int.parse(m[1]!);
  final suffix = h >= 12 ? 'PM' : 'AM';
  final hour12 = h % 12 == 0 ? 12 : h % 12;
  return '$hour12:${m[2]} $suffix';
}

/// JavaScript's `Number(x)` printed: "3.00" → "3", "2.50" → "2.5".
String numText(Object? value) {
  final n = num.tryParse('${value ?? ''}');
  if (n == null) return '${value ?? ''}';
  if (n == n.roundToDouble()) return n.toInt().toString();
  var s = n.toString();
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'0+$'), '');
  return s;
}

num numOf(Object? value) => num.tryParse('${value ?? ''}') ?? 0;

/// "3 hours" / "1 hour".
String hoursLabel(Object? hours) => '${numText(hours)} hour${numOf(hours) == 1 ? '' : 's'}';

/// The web's formatDateOnly: "Nov 23, 2026"; '—' when missing.
String formatDateOnly(Object? value) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch('${value ?? ''}');
  if (value == null || '$value'.isEmpty) return '—';
  if (m == null) return '$value';
  return DateFormat('MMM d, yyyy').format(DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)));
}

/// The web's formatDateTime (en-PH): "Nov 23, 2026, 3:45 PM", in Manila time.
String formatDateTime(Object? value) {
  if (value == null || '$value'.isEmpty) return '';
  final utc = ManilaTime.parseUtc('$value');
  if (utc == null) return '$value';
  return DateFormat('MMM d, yyyy, h:mm a').format(ManilaTime.toManila(utc));
}

/// Today as the employee's calendar day (Manila — the company's zone).
String manilaToday([DateTime? now]) {
  final d = ManilaTime.toManila((now ?? DateTime.now()).toUtc());
  String p(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${p(d.month)}-${p(d.day)}';
}

String _s(Object? v) => v == null ? '' : '$v';
String? _sn(Object? v) => v == null || '$v'.isEmpty ? null : '$v';
int _i(Object? v) => v is int ? v : int.tryParse('${v ?? ''}') ?? 0;

class OvertimePhoto {
  final int id;
  final String fileUrl;
  const OvertimePhoto({required this.id, required this.fileUrl});
  factory OvertimePhoto.fromJson(Map<String, dynamic> j) => OvertimePhoto(id: _i(j['id']), fileUrl: _s(j['file_url']));
}

/// One covered date of a filing (migration 042).
class OvertimeDate {
  final int id;
  final String date; // YYYY-MM-DD
  final String? accomplishmentAt;
  final String? accomplishmentNote;
  final List<OvertimePhoto> photos;

  const OvertimeDate({
    required this.id,
    required this.date,
    this.accomplishmentAt,
    this.accomplishmentNote,
    this.photos = const [],
  });

  bool get submitted => accomplishmentAt != null;

  factory OvertimeDate.fromJson(Map<String, dynamic> j) => OvertimeDate(
        id: _i(j['id']),
        date: _s(j['date']).length >= 10 ? _s(j['date']).substring(0, 10) : _s(j['date']),
        accomplishmentAt: _sn(j['accomplishment_at']),
        accomplishmentNote: _sn(j['accomplishment_note']),
        photos: ((j['photos'] as List?) ?? const []).whereType<Map<String, dynamic>>().map(OvertimePhoto.fromJson).toList(),
      );
}

/// One filing, as GET /api/me/overtime-requests lists it.
class OvertimeRequest {
  final int id;
  final String status;
  final String otType;
  final Object? otHours;
  final String? startTime;
  final String? endTime;
  final String? purpose;
  final String? attachmentUrl;
  final List<String> attachmentUrls;
  final int? assignedBy;
  final String? assignedByName;
  final List<OvertimeDate> dates;
  final int dateCount;
  final int accomplishmentsOutstanding;

  const OvertimeRequest({
    required this.id,
    required this.status,
    required this.otType,
    this.otHours,
    this.startTime,
    this.endTime,
    this.purpose,
    this.attachmentUrl,
    this.attachmentUrls = const [],
    this.assignedBy,
    this.assignedByName,
    this.dates = const [],
    this.dateCount = 0,
    this.accomplishmentsOutstanding = 0,
  });

  bool get holiday => isHolidayWork(otType);

  /// `(r.attachment_urls || [r.attachment_url]).filter(Boolean)`.
  List<String> get files => attachmentUrls.isNotEmpty ? attachmentUrls : [?attachmentUrl];

  factory OvertimeRequest.fromJson(Map<String, dynamic> j) {
    final urls = j['attachment_urls'];
    final dates = ((j['dates'] as List?) ?? const []).whereType<Map<String, dynamic>>().map(OvertimeDate.fromJson).toList();
    return OvertimeRequest(
      id: _i(j['id']),
      status: _s(j['status']),
      otType: _s(j['ot_type']),
      otHours: j['ot_hours'],
      startTime: _sn(j['start_time']),
      endTime: _sn(j['end_time']),
      purpose: _sn(j['purpose']),
      attachmentUrl: _sn(j['attachment_url']),
      attachmentUrls: urls is List ? urls.where((u) => u != null && '$u'.isNotEmpty).map((u) => '$u').toList() : const [],
      assignedBy: j['assigned_by'] == null ? null : _i(j['assigned_by']),
      assignedByName: _sn(j['assigned_by_name']),
      dates: dates,
      dateCount: j['date_count'] == null ? dates.length : _i(j['date_count']),
      accomplishmentsOutstanding: _i(j['accomplishments_outstanding']),
    );
  }
}

class OvertimePagination {
  final int page;
  final int limit;
  final int total;
  final int totalPages;
  const OvertimePagination({this.page = 1, this.limit = 20, this.total = 0, this.totalPages = 0});
  factory OvertimePagination.fromJson(Map<String, dynamic>? j) => j == null
      ? const OvertimePagination()
      : OvertimePagination(
          page: _i(j['page']) == 0 ? 1 : _i(j['page']),
          limit: _i(j['limit']) == 0 ? 20 : _i(j['limit']),
          total: _i(j['total']),
          totalPages: _i(j['totalPages']),
        );
}

class OvertimePage {
  final List<OvertimeRequest> items;
  final OvertimePagination pagination;
  const OvertimePage({this.items = const [], this.pagination = const OvertimePagination()});
  factory OvertimePage.fromJson(Map<String, dynamic>? j) => OvertimePage(
        items: ((j?['items'] as List?) ?? const []).whereType<Map<String, dynamic>>().map(OvertimeRequest.fromJson).toList(),
        pagination: OvertimePagination.fromJson(j?['pagination'] as Map<String, dynamic>?),
      );
}

class HolidayTitle {
  final String date;
  final String title;
  const HolidayTitle(this.date, this.title);
}

/// GET /api/me/overtime-window — the server-derived window and what it would pay.
class OvertimeWindow {
  final bool isHoliday;
  final Object? hours;
  final String? kindLabel;
  final List<HolidayTitle> holidays;
  final Object? maxHours;
  final String? startTime;
  final String? endTime;
  final String? scheduleEnd;
  final Object? gapMinutes;
  final String? earliestStart;
  final Object? estimatedPay;
  final Object? estimatedPremium;

  const OvertimeWindow({
    this.isHoliday = false,
    this.hours,
    this.kindLabel,
    this.holidays = const [],
    this.maxHours,
    this.startTime,
    this.endTime,
    this.scheduleEnd,
    this.gapMinutes,
    this.earliestStart,
    this.estimatedPay,
    this.estimatedPremium,
  });

  factory OvertimeWindow.fromJson(Map<String, dynamic> j) => OvertimeWindow(
        isHoliday: j['is_holiday'] == true,
        hours: j['hours'],
        kindLabel: _sn(j['kind_label']),
        holidays: ((j['holidays'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map((h) => HolidayTitle(_s(h['date']), _s(h['title'])))
            .toList(),
        maxHours: j['max_hours'],
        startTime: _sn(j['start_time']),
        endTime: _sn(j['end_time']),
        scheduleEnd: _sn(j['schedule_end']),
        gapMinutes: j['gap_minutes'],
        earliestStart: _sn(j['earliest_start']),
        estimatedPay: j['estimated_pay'],
        estimatedPremium: j['estimated_premium'],
      );
}

/// Who the filing is for — read from GET /api/me/profile, never typed.
class OvertimeIdentity {
  final String fullName;
  final String? department;
  final String? designation;
  const OvertimeIdentity({this.fullName = '', this.department, this.designation});
  factory OvertimeIdentity.fromJson(Map<String, dynamic> j) => OvertimeIdentity(
        fullName: [j['first_name'], j['middle_name'], j['last_name'], j['suffix']]
            .where((p) => p != null && '$p'.isNotEmpty)
            .join(' '),
        department: _sn(j['department_name']),
        designation: _sn(j['designation_name']),
      );
}

class ReportStep {
  final Object? level;
  final String action;
  final String? approverName;
  final String? approverRole;
  final String? actedAt;
  final String? remarks;
  const ReportStep({this.level, required this.action, this.approverName, this.approverRole, this.actedAt, this.remarks});
  factory ReportStep.fromJson(Map<String, dynamic> j) {
    final a = j['approver'] as Map<String, dynamic>?;
    return ReportStep(
      level: j['level'],
      action: _s(j['action']),
      approverName: _sn(a?['username']),
      approverRole: _sn(a?['role_name']),
      actedAt: _sn(j['acted_at']),
      remarks: _sn(j['remarks']),
    );
  }
}

/// GET /api/me/overtime-requests/:id/report — the accomplishment report.
class OvertimeReport {
  final int id;
  final String status;
  final String otType;
  final Object? otHours;
  final String? startTime;
  final String? endTime;
  final String? purpose;
  final String? dateFiled;
  final String? companyName;
  final String? companyCode;
  final Map<String, dynamic> employee;
  final List<ReportStep> steps;
  final List<OvertimeDate> dates;
  final int? dateCount;
  final int reportedCount;
  final int photoCount;

  const OvertimeReport({
    required this.id,
    required this.status,
    required this.otType,
    this.otHours,
    this.startTime,
    this.endTime,
    this.purpose,
    this.dateFiled,
    this.companyName,
    this.companyCode,
    this.employee = const {},
    this.steps = const [],
    this.dates = const [],
    this.dateCount,
    this.reportedCount = 0,
    this.photoCount = 0,
  });

  String get refNo => 'OT-${id.toString().padLeft(5, '0')}';

  factory OvertimeReport.fromJson(Map<String, dynamic> j) {
    final company = j['company'] as Map<String, dynamic>?;
    final summary = j['summary'] as Map<String, dynamic>?;
    final approval = j['approval'] as Map<String, dynamic>?;
    return OvertimeReport(
      id: _i(j['id']),
      status: _s(j['status']),
      otType: _s(j['ot_type']),
      otHours: j['ot_hours'],
      startTime: _sn(j['start_time']),
      endTime: _sn(j['end_time']),
      purpose: _sn(j['purpose']),
      dateFiled: _sn(j['date_filed']),
      companyName: _sn(company?['name']),
      companyCode: _sn(company?['code']),
      employee: (j['employee'] as Map<String, dynamic>?) ?? const {},
      steps: ((approval?['steps'] as List?) ?? const []).whereType<Map<String, dynamic>>().map(ReportStep.fromJson).toList(),
      dates: ((j['dates'] as List?) ?? const []).whereType<Map<String, dynamic>>().map(OvertimeDate.fromJson).toList(),
      dateCount: summary?['date_count'] == null ? null : _i(summary!['date_count']),
      reportedCount: _i(summary?['reported_count']),
      photoCount: _i(summary?['photo_count']),
    );
  }
}
