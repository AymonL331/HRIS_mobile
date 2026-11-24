import '../../core/format/money.dart';
import '../my_profile/web_format.dart';

/// GET /api/me/dashboard (services/meDashboard.service.js#getSummary).
class MyDashboard {
  final int leaveYear;
  final List<LeaveBalanceLine> balances;
  final num totalRemaining;
  final LatestPayslip? latestPayslip;
  final PendingRequests pending;
  final List<UpcomingHoliday> holidays;

  const MyDashboard({
    required this.leaveYear,
    required this.balances,
    required this.totalRemaining,
    required this.latestPayslip,
    required this.pending,
    required this.holidays,
  });

  factory MyDashboard.fromJson(Map<String, dynamic> j) {
    final leave = asJsonMap(j['leave']) ?? const {};
    final p = j['latest_payslip'];
    return MyDashboard(
      leaveYear: Money.asNum(leave['year']).toInt(),
      balances: ((leave['balances'] as List?) ?? const [])
          .map(asJsonMap)
          .whereType<Map<String, dynamic>>()
          .map(LeaveBalanceLine.fromJson)
          .toList(),
      totalRemaining: Money.asNum(leave['total_remaining']),
      latestPayslip: p is Map ? LatestPayslip.fromJson(asJsonMap(p)!) : null,
      pending: PendingRequests.fromJson(asJsonMap(j['pending_requests']) ?? const {}),
      holidays: ((j['upcoming_holidays'] as List?) ?? const [])
          .map(asJsonMap)
          .whereType<Map<String, dynamic>>()
          .map(UpcomingHoliday.fromJson)
          .toList(),
    );
  }
}

class LeaveBalanceLine {
  final int leaveTypeId;
  final String leaveType;
  final num accrued;
  final num remaining;

  const LeaveBalanceLine({required this.leaveTypeId, required this.leaveType, required this.accrued, required this.remaining});

  factory LeaveBalanceLine.fromJson(Map<String, dynamic> j) => LeaveBalanceLine(
        leaveTypeId: Money.asNum(j['leave_type_id']).toInt(),
        leaveType: '${j['leave_type'] ?? 'Leave'}',
        accrued: Money.asNum(j['accrued']),
        remaining: Money.asNum(j['remaining']),
      );
}

class LatestPayslip {
  final int id;
  final Object? netPay;
  final String status;
  final String? periodStart;
  final String? periodEnd;

  const LatestPayslip({required this.id, required this.netPay, required this.status, this.periodStart, this.periodEnd});

  factory LatestPayslip.fromJson(Map<String, dynamic> j) => LatestPayslip(
        id: Money.asNum(j['id']).toInt(),
        netPay: j['net_pay'],
        status: '${j['status'] ?? ''}',
        periodStart: j['period_start'] as String?,
        periodEnd: j['period_end'] as String?,
      );
}

class PendingRequests {
  final int leave;
  final int corrections;
  final int travelOrders;
  final int total;

  const PendingRequests({required this.leave, required this.corrections, required this.travelOrders, required this.total});

  factory PendingRequests.fromJson(Map<String, dynamic> j) => PendingRequests(
        leave: Money.asNum(j['leave']).toInt(),
        corrections: Money.asNum(j['corrections']).toInt(),
        travelOrders: Money.asNum(j['travel_orders']).toInt(),
        total: Money.asNum(j['total']).toInt(),
      );
}

class UpcomingHoliday {
  final int id;
  final String title;
  final String date;

  const UpcomingHoliday({required this.id, required this.title, required this.date});

  factory UpcomingHoliday.fromJson(Map<String, dynamic> j) =>
      UpcomingHoliday(id: Money.asNum(j['id']).toInt(), title: '${j['title'] ?? ''}', date: '${j['date'] ?? ''}');
}

/// A day count as the web prints a JS number: 12 → "12", 1.5 → "1.5".
String numText(num n) => n == n.roundToDouble() ? n.toInt().toString() : n.toString();
