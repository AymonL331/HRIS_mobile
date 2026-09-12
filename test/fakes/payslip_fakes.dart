import 'package:hris_mobile/core/http/api_exception.dart';
import 'package:hris_mobile/features/payslips/payslip_api.dart';
import 'package:hris_mobile/features/payslips/payslip_breakdown_models.dart';
import 'package:hris_mobile/features/payslips/payslip_models.dart';

/// One row of `GET /api/me/payslips`, as the server sends it — DECIMAL money as
/// STRINGS, because that is what mysql2 returns for DECIMAL(15,2) and parsing
/// it is half the job.
Map<String, dynamic> payslipRow(
  int id, {
  String status = 'released',
  String? transactionDate = '2026-08-20',
  String netPay = '12480.50',
  Map<String, dynamic>? run = const {
    'id': 7,
    'name': null,
    'type': 'normal',
    'period_start': '2026-08-01',
    'period_end': '2026-08-15',
  },
}) =>
    {
      'id': id,
      'employee_id': 2316,
      'status': status,
      'transaction_date': transactionDate,
      'net_pay': netPay,
      'basic_pay': '13900.00',
      'total_earnings': '14120.00',
      'total_deductions': '1639.50',
      'sss_ee': '675.00',
      'philhealth_ee': '347.50',
      'pagibig_ee': '100.00',
      'wht': '517.00',
      // What the server also sends and the payslip screens must never show —
      // the EMPLOYER's share is nobody's deduction.
      'sss_er': '1350.00',
      'philhealth_er': '347.50',
      'pagibig_er': '100.00',
      'run': run,
    };

/// `GET /api/me/payslips/:id` → `{ payslip, items }`.
Map<String, dynamic> payslipDetail(int id, {List<Map<String, dynamic>>? items, Map<String, dynamic>? payslip}) => {
      'payslip': payslip ?? payslipRow(id),
      'items': items ??
          [
            item(1, 'earning', 'Basic pay', '13900.00'),
            item(2, 'earning', 'Overtime (regular)', '220.00', taxable: 1),
            item(3, 'allowance', 'Meal allowance', '500.00'),
            item(4, 'contribution', 'SSS', '675.00'),
            item(5, 'deduction', 'Late / undertime', '417.50'),
            item(6, 'tax', 'Withholding tax', '517.00'),
          ],
    };

Map<String, dynamic> item(int id, String category, String name, String amount, {int taxable = 0}) =>
    {'id': id, 'category': category, 'name': name, 'amount': amount, 'taxable': taxable};

/// `GET /api/me/payslips/:id/breakdown`.
Map<String, dynamic> breakdownPayload({
  bool attendanceDriven = true,
  bool reconciles = true,
  List<Map<String, dynamic>>? basicDays,
  List<Map<String, dynamic>>? deductionDays,
  List<Map<String, dynamic>>? overtimeDays,
}) =>
    {
      'salary_type': 'daily',
      'daily_rate': 695,
      'hourly_rate': 86.875,
      'period': {'from': '2026-08-01', 'to': '2026-08-15'},
      'basic': {
        'amount': '13900.00',
        'attendance_driven': attendanceDriven,
        'paid_days': 20,
        'credited_days': 20,
        'reconciles': reconciles,
        'days': basicDays ??
            [
              {'date': '2026-08-04', 'status': 'present', 'credited': true, 'reason': null},
              {'date': '2026-08-06', 'status': 'present', 'credited': false, 'reason': 'No time out recorded'},
            ],
      },
      'late': {'paid': '417.50', 'recomputed': '417.50', 'reconciles': true},
      'undertime': {'paid': '0.00', 'recomputed': '0.00', 'reconciles': true},
      'deduction_days': deductionDays ??
          [
            {
              'date': '2026-08-04',
              'late_minutes': 16,
              'undertime_minutes': 0,
              'leave_cover': null,
              'leave_covered_minutes': 0,
              'chargeable_late_minutes': 16,
              'chargeable_undertime_minutes': 0,
              'late_hours': 0.27,
              'late_amount': 23.46,
              'undertime_hours': 0,
              'undertime_amount': 0,
            },
          ],
      'overtime_days': overtimeDays ??
          [
            {
              'date': '2026-08-07',
              'ot_type': 'regular',
              'hours': 3,
              'amount': 286.68,
              'paid': true,
              'reason': null,
              'is_catch_up': false,
              'multiplier': 1.1,
              'rate_per_hour': 95.56,
            },
          ],
      'overtime_hourly_rate': 86.875,
      'grace_minutes': 15,
    };

/// A scriptable [PayslipApi]. Each call records itself so a test can assert
/// WHICH page was asked for, and any of the three can be made to fail.
class FakePayslipApi implements PayslipApi {
  final List<Map<String, dynamic>> rows;
  final Map<String, dynamic>? detailPayload;
  final Map<String, dynamic>? breakdownJson;
  final int totalPages;

  Object? listError;
  Object? detailError;
  Object? breakdownError;
  final calls = <String>[];

  FakePayslipApi({
    this.rows = const [],
    this.detailPayload,
    this.breakdownJson,
    this.totalPages = 1,
  });

  @override
  Future<PayslipPage> list({required int page, int limit = 20}) async {
    calls.add('list:$page:$limit');
    if (listError != null) throw listError!;
    // One row per page, keyed off the page number, so an append is visible.
    final start = (page - 1) * limit;
    final slice = start >= rows.length ? const <Map<String, dynamic>>[] : rows.skip(start).take(limit).toList();
    return PayslipPage(
      items: slice.map(PayslipSummary.fromJson).toList(),
      page: page,
      totalPages: totalPages,
      total: rows.length,
    );
  }

  @override
  Future<Payslip> detail(int id) async {
    calls.add('detail:$id');
    if (detailError != null) throw detailError!;
    return Payslip.fromJson(detailPayload ?? payslipDetail(id));
  }

  @override
  Future<PayslipBreakdown> breakdown(int id) async {
    calls.add('breakdown:$id');
    if (breakdownError != null) throw breakdownError!;
    return PayslipBreakdown.fromJson(breakdownJson ?? breakdownPayload());
  }
}

const notFound = ApiException(status: 404, message: 'Payslip not found.');

/// `GET /api/me/payslips/16391/breakdown` on the sandbox (employee sofia),
/// captured verbatim on 2026-09-12. Kept as REAL server output so the parser is
/// pinned to what the API sends rather than to what the fakes above assume:
/// `daily_rate` and `hourly_rate` arrive as NUMBERS here while the payslip's own
/// money arrives as DECIMAL strings, and this payslip genuinely does not
/// reconcile (attendance was corrected after the run).
const sandboxBreakdown = <String, dynamic>{
  'salary_type': 'daily',
  'daily_rate': 695,
  'hourly_rate': 86.875,
  'period': {'from': '2026-08-12', 'to': '2026-08-14'},
  'basic': {
    'amount': 1390,
    'attendance_driven': true,
    'paid_days': 2,
    'credited_days': 1,
    'reconciles': false,
    'days': [
      {
        'date': '2026-08-12',
        'clock_in_at': '2026-08-12T00:15:00.000Z',
        'clock_out_at': '2026-08-12T13:44:00.000Z',
        'status': 'present',
        'credited': true,
        'reason': null,
      },
      {
        'date': '2026-08-13',
        'clock_in_at': '2026-08-13T03:20:52.000Z',
        'clock_out_at': null,
        'status': 'late',
        'credited': false,
        'reason': 'No time out recorded',
      },
      {
        'date': '2026-08-14',
        'clock_in_at': null,
        'clock_out_at': null,
        'status': 'absent',
        'credited': false,
        'reason': 'Absent — no time in',
      },
    ],
  },
  'late': {'paid': 23.46, 'recomputed': 347.5, 'reconciles': false},
  'undertime': {'paid': 0, 'recomputed': 0, 'reconciles': true},
  'deduction_days': [
    {
      'date': '2026-08-13',
      'late_minutes': 200,
      'undertime_minutes': 0,
      'leave_cover': null,
      'leave_covered_minutes': 0,
      'chargeable_late_minutes': 200,
      'chargeable_undertime_minutes': 0,
      'late_hours': 4,
      'late_amount': 347.5,
      'undertime_hours': 0,
      'undertime_amount': 0,
    },
  ],
  'overtime_days': [
    {
      'date': '2026-08-12',
      'ot_type': 'ordinary',
      'hours': 3,
      'amount': 286.68,
      'paid': true,
      'reason': null,
      'is_catch_up': false,
      'clock_out_at': '2026-08-12T13:44:00.000Z',
      'required_until': '2026-08-12T13:00:00.000Z',
      'multiplier': 1.1,
      'rate_per_hour': 95.56,
    },
    {
      'date': '2026-08-13',
      'ot_type': 'ordinary',
      'hours': 3,
      'amount': 0,
      'paid': false,
      'reason': 'No clock-out on this date — approved overtime is paid only when it is worked',
      'is_catch_up': false,
      'clock_out_at': null,
      'required_until': '2026-08-13T13:00:00.000Z',
    },
    {
      'date': '2026-08-14',
      'ot_type': 'ordinary',
      'hours': 3,
      'amount': 0,
      'paid': false,
      'reason': 'No accomplishment report submitted',
      'is_catch_up': false,
    },
  ],
  'overtime_hourly_rate': 86.875,
  'grace_minutes': 15,
};
