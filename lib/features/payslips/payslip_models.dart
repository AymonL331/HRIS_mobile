import 'package:intl/intl.dart';

import '../../core/format/money.dart';
import 'payslip_enums.dart';

int? _id(Object? v) => v == null ? null : (v is int ? v : int.tryParse('$v'));
bool _flag(Object? v) => v == true || v == 1 || v == '1';

/// A DATE column ('YYYY-MM-DD') → "Aug 1, 2026".
///
/// The 'YYYY-MM-DD' prefix is parsed by hand into a LOCAL calendar date, never
/// through a timezone-shifting parse: a transaction date or a payroll period
/// boundary is a calendar day, not an instant, and shifting it can move it a
/// day. This is the web's `formatDateOnly`, dash and all.
String formatDateOnly(Object? value) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch('${value ?? ''}');
  if (m == null) return value == null || '$value'.isEmpty ? '—' : '$value';
  return DateFormat('MMM d, y').format(DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)));
}

/// The same date as "Aug 6" — the breakdown's per-day column, where the year is
/// already established by the payslip above it.
String formatShortDate(Object? value) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch('${value ?? ''}');
  if (m == null) return '${value ?? ''}';
  return DateFormat('MMM d').format(DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)));
}

/// Which payroll run paid a payslip (`payslips.payroll_run_id`, LEFT JOINed by
/// the server into a `run` object — null when the run is gone).
class PayrollRunRef {
  final int id;
  final String? name;
  final String? type;
  final String? periodStart;
  final String? periodEnd;

  const PayrollRunRef({
    required this.id,
    required this.name,
    required this.type,
    required this.periodStart,
    required this.periodEnd,
  });

  static PayrollRunRef? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final id = _id(raw['id']);
    if (id == null) return null;
    return PayrollRunRef(
      id: id,
      name: raw['name'] as String?,
      type: raw['type'] as String?,
      periodStart: raw['period_start'] as String?,
      periodEnd: raw['period_end'] as String?,
    );
  }

  /// The web's `runDisplayName`: the run's own name when it has one, else the
  /// derived `<Type> run · <period>` label. Identical to the website's so a
  /// payslip is identified the same way on the phone as in the browser.
  String get displayName {
    final trimmed = (name ?? '').trim();
    if (trimmed.isNotEmpty) return trimmed;
    final label = payrollRunTypeLabels[type] ?? (type == null || type!.isEmpty ? 'Payroll' : type!);
    return '$label run · ${formatDateOnly(periodStart)} – ${formatDateOnly(periodEnd)}';
  }
}

/// One row of `GET /api/me/payslips` — the fields the list shows. The endpoint
/// returns the whole payslip, but a list row only needs these; the detail
/// screen re-reads the payslip in full.
class PayslipSummary {
  final int id;
  final String? status;
  final String? transactionDate;
  final num netPay;
  final PayrollRunRef? run;

  const PayslipSummary({
    required this.id,
    required this.status,
    required this.transactionDate,
    required this.netPay,
    required this.run,
  });

  factory PayslipSummary.fromJson(Map<String, dynamic> j) => PayslipSummary(
        id: _id(j['id']) ?? 0,
        status: j['status'] as String?,
        transactionDate: j['transaction_date'] as String?,
        netPay: Money.asNum(j['net_pay']),
        run: PayrollRunRef.fromJson(j['run']),
      );
}

/// One itemised line (`payslip_items`).
class PayslipItem {
  final int id;
  final String category;
  final String name;
  final num amount;
  final bool taxable;

  const PayslipItem({
    required this.id,
    required this.category,
    required this.name,
    required this.amount,
    required this.taxable,
  });

  factory PayslipItem.fromJson(Map<String, dynamic> j) => PayslipItem(
        id: _id(j['id']) ?? 0,
        category: (j['category'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        amount: Money.asNum(j['amount']),
        taxable: _flag(j['taxable']),
      );
}

/// One payslip with its lines — `GET /api/me/payslips/:id` → `{ payslip, items }`.
///
/// Carries the EMPLOYEE-share statutory columns only. `sss_er`, `philhealth_er`
/// and `pagibig_er` are the employer's cost, are not withheld from anybody's
/// pay, and are not on the web payslip either — the parser drops them so they
/// cannot reach this screen by accident.
class Payslip {
  final int id;
  final String? status;
  final String? transactionDate;
  final num basicPay;
  final num totalEarnings;
  final num totalDeductions;
  final num netPay;
  final num sssEe;
  final num philhealthEe;
  final num pagibigEe;
  final num wht;
  final PayrollRunRef? run;
  final List<PayslipItem> items;

  const Payslip({
    required this.id,
    required this.status,
    required this.transactionDate,
    required this.basicPay,
    required this.totalEarnings,
    required this.totalDeductions,
    required this.netPay,
    required this.sssEe,
    required this.philhealthEe,
    required this.pagibigEe,
    required this.wht,
    required this.run,
    required this.items,
  });

  factory Payslip.fromJson(Map<String, dynamic> data) {
    final p = (data['payslip'] as Map<String, dynamic>?) ?? const {};
    final rawItems = (data['items'] as List?) ?? const [];
    return Payslip(
      id: _id(p['id']) ?? 0,
      status: p['status'] as String?,
      transactionDate: p['transaction_date'] as String?,
      basicPay: Money.asNum(p['basic_pay']),
      totalEarnings: Money.asNum(p['total_earnings']),
      totalDeductions: Money.asNum(p['total_deductions']),
      netPay: Money.asNum(p['net_pay']),
      sssEe: Money.asNum(p['sss_ee']),
      philhealthEe: Money.asNum(p['philhealth_ee']),
      pagibigEe: Money.asNum(p['pagibig_ee']),
      wht: Money.asNum(p['wht']),
      run: PayrollRunRef.fromJson(p['run']),
      items: rawItems.whereType<Map<String, dynamic>>().map(PayslipItem.fromJson).toList(growable: false),
    );
  }

  /// The lines grouped into the web's ordered category buckets. Categories the
  /// payslip has no lines for are dropped, so no empty heading is left behind.
  List<PayslipItemGroup> get groupedItems {
    final buckets = <String, List<PayslipItem>>{};
    for (final item in items) {
      buckets.putIfAbsent(item.category, () => []).add(item);
    }
    return [
      for (final category in payslipItemCategoryOrder)
        if (buckets.containsKey(category)) PayslipItemGroup(category, buckets[category]!),
    ];
  }
}

class PayslipItemGroup {
  final String category;
  final List<PayslipItem> items;

  const PayslipItemGroup(this.category, this.items);

  String get label => payslipItemCategoryLabels[category] ?? category;
}
