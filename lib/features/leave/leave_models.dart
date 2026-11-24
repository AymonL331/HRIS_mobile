import '../../core/format/money.dart';
import '../../shared/widgets/status_badge.dart';

/// MY LEAVE — the web's /api/me/leave/* payloads (hris/client/src/pages/employee
/// MyLeavePage.jsx + constants/leaveEnums.js). DECIMAL columns (days, accrued,
/// used, remaining) reach the client as STRINGS, so every figure goes through
/// [Money.toNum]; DATE columns are plain 'YYYY-MM-DD' (db.js dateStrings).

/// leave_requests.status ENUM — LEAVE_STATUS_LABELS.
const leaveStatusLabels = {
  'pending': 'Pending',
  'approved': 'Approved',
  'rejected': 'Rejected',
  'cancelled': 'Cancelled',
};

/// LEAVE_STATUS_TONE.
StatusTone leaveStatusTone(String? status) => switch (status) {
      'pending' => StatusTone.warning,
      'approved' => StatusTone.success,
      'rejected' => StatusTone.danger,
      _ => StatusTone.neutral,
    };

/// leave_types.payment_type — PAYMENT_TYPE_LABELS.
const paymentTypeLabels = {'paid': 'Paid', 'unpaid': 'Unpaid'};

/// leave_requests.day_part (migration 036) — LEAVE_DAY_PART_LABELS, in the web's order.
const leaveDayPartLabels = {
  'full': 'Full day',
  'am_half': 'Morning half (AM)',
  'pm_half': 'Afternoon half (PM)',
};

/// CANCELLABLE_LEAVE_STATUSES — mirrors leave.service.cancelRequest.
// Pending only: once approved, only an admin cancels it (user 2026-11-24; the
// server refuses it on /api/me too).
const cancellableLeaveStatuses = ['pending'];

/// JavaScript's `Number(x)` as text: 3 → "3", "0.50" → "0.5", "15.00" → "15".
String jsNumber(Object? value) {
  final n = Money.toNum(value);
  if (n == null) return 'NaN';
  if (n == n.roundToDouble()) return n.toInt().toString();
  var s = n.toString();
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return s;
}

int _int(Object? v) => v is int ? v : int.tryParse('$v') ?? 0;
String _date(Object? v) {
  final s = v?.toString() ?? '';
  return s.length >= 10 ? s.substring(0, 10) : s;
}

class LeaveType {
  final int id;
  final String name;
  final String? paymentType;

  const LeaveType({required this.id, required this.name, this.paymentType});

  factory LeaveType.fromJson(Map<String, dynamic> j) =>
      LeaveType(id: _int(j['id']), name: '${j['name'] ?? ''}', paymentType: j['payment_type'] as String?);

  /// The picker's label: "Vacation Leave (Paid)".
  String get optionLabel {
    final p = paymentTypeLabels[paymentType];
    return p == null ? name : '$name ($p)';
  }
}

class LeaveBalance {
  final int id;
  final int leaveTypeId;
  final Object? year;
  final Object? accrued;
  final Object? used;
  final Object? remaining;

  const LeaveBalance({
    required this.id,
    required this.leaveTypeId,
    this.year,
    this.accrued,
    this.used,
    this.remaining,
  });

  factory LeaveBalance.fromJson(Map<String, dynamic> j) => LeaveBalance(
        id: _int(j['id']),
        leaveTypeId: _int(j['leave_type_id']),
        year: j['year'],
        accrued: j['accrued'],
        used: j['used'],
        remaining: j['remaining'],
      );
}

class LeaveRequestRow {
  final int id;
  final int leaveTypeId;
  final String dateFrom;
  final String dateTo;
  final String? dayPart;
  final Object? days;
  final String? status;

  const LeaveRequestRow({
    required this.id,
    required this.leaveTypeId,
    required this.dateFrom,
    required this.dateTo,
    this.dayPart,
    this.days,
    this.status,
  });

  factory LeaveRequestRow.fromJson(Map<String, dynamic> j) => LeaveRequestRow(
        id: _int(j['id']),
        leaveTypeId: _int(j['leave_type_id']),
        dateFrom: _date(j['date_from']),
        dateTo: _date(j['date_to']),
        dayPart: j['day_part'] as String?,
        days: j['days'],
        status: j['status'] as String?,
      );

  bool get cancellable => cancellableLeaveStatuses.contains(status);

  /// The Days cell: "1", "0.5 (AM)", "0.5 (PM)".
  String get daysLabel =>
      jsNumber(days) + (dayPart == 'am_half' ? ' (AM)' : dayPart == 'pm_half' ? ' (PM)' : '');
}

/// `{ items, pagination: { page, limit, total, totalPages } }`.
class LeaveRequestPage {
  final List<LeaveRequestRow> items;
  final int page;
  final int total;
  final int totalPages;

  const LeaveRequestPage({required this.items, this.page = 1, this.total = 0, this.totalPages = 0});

  factory LeaveRequestPage.fromJson(Map<String, dynamic> j) {
    final p = (j['pagination'] as Map<String, dynamic>?) ?? const {};
    return LeaveRequestPage(
      items: ((j['items'] as List?) ?? const []).whereType<Map<String, dynamic>>().map(LeaveRequestRow.fromJson).toList(),
      page: p['page'] == null ? 1 : _int(p['page']),
      total: _int(p['total']),
      totalPages: _int(p['totalPages']),
    );
  }
}
