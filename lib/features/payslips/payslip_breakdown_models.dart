import '../../core/format/money.dart';

int _int(Object? v) => Money.toNum(v)?.round() ?? 0;
int? _intOrNull(Object? v) => Money.toNum(v)?.round();
bool _flag(Object? v) => v == true || v == 1 || v == '1';
bool _flagTrue(Object? v, {bool orElse = true}) => v == null ? orElse : _flag(v);

/// "Where did this figure come from?" — the working behind a payslip, for the
/// person whose money it is, from `GET /api/me/payslips/:id/breakdown`.
///
/// Everything here is computed SERVER-side by the same function that priced the
/// run, so the phone can never quote arithmetic the payment did not use. It is
/// derived at read time, so if attendance was corrected after payroll ran the
/// rebuilt total can disagree with what was paid — the server says so
/// ([reconciles]) and the screen renders that as a warning rather than quietly
/// showing a second, different number.
///
/// The models carry the SENTENCES ([DeductionDay.note], [OvertimeDay.note])
/// rather than leaving them to the widgets: they are the part most easily got
/// wrong, and this way they are unit-tested without pumping a screen.
class PayslipBreakdown {
  final String? salaryType;
  final num dailyRate;
  final num? hourlyRate;
  final BasicBlock basic;
  final TardinessTotal late;
  final TardinessTotal undertime;
  final List<DeductionDay> deductionDays;
  final List<OvertimeDay> overtimeDays;
  final num? overtimeHourlyRate;
  final int graceMinutes;

  const PayslipBreakdown({
    required this.salaryType,
    required this.dailyRate,
    required this.hourlyRate,
    required this.basic,
    required this.late,
    required this.undertime,
    required this.deductionDays,
    required this.overtimeDays,
    required this.overtimeHourlyRate,
    required this.graceMinutes,
  });

  factory PayslipBreakdown.fromJson(Map<String, dynamic> j) => PayslipBreakdown(
        salaryType: j['salary_type'] as String?,
        dailyRate: Money.asNum(j['daily_rate']),
        hourlyRate: Money.toNum(j['hourly_rate']),
        basic: BasicBlock.fromJson((j['basic'] as Map<String, dynamic>?) ?? const {}),
        late: TardinessTotal.fromJson((j['late'] as Map<String, dynamic>?) ?? const {}),
        undertime: TardinessTotal.fromJson((j['undertime'] as Map<String, dynamic>?) ?? const {}),
        deductionDays: ((j['deduction_days'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(DeductionDay.fromJson)
            .toList(growable: false),
        overtimeDays: ((j['overtime_days'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(OvertimeDay.fromJson)
            .toList(growable: false),
        overtimeHourlyRate: Money.toNum(j['overtime_hourly_rate']),
        graceMinutes: _int(j['grace_minutes']),
      );

  /// Attendance changed after the run, so the rebuilt figures no longer add up
  /// to what was paid. The payslip figures stand; the working is what is stale.
  bool get mismatched => !basic.reconciles || !late.reconciles || !undertime.reconciles;

  bool get hasDeductions => late.paid > 0 || undertime.paid > 0 || deductionDays.isNotEmpty;

  num get deductionsTotal => late.paid + undertime.paid;

  num get overtimeTotal => overtimeDays.fold<num>(0, (sum, d) => sum + d.amount);

  /// The premium rate is the same for every date of one classification, so the
  /// formula line quotes it once — taken from the first PAID date rather than
  /// recomputed here (the company rounds the per-hour premium FIRST and then
  /// multiplies, so dividing an amount back out gives a different number).
  OvertimeDay? get ratedOvertimeDay {
    for (final d in overtimeDays) {
      if (d.paid && d.ratePerHour != null) return d;
    }
    return null;
  }

  /// Does any date on this payslip pay overtime worked BEFORE the period it
  /// covers (migration 044)? Only then is the "earlier period" note shown — a
  /// standing explanation of a rare case would be noise on every other payslip.
  bool get hasCatchUp => overtimeDays.any((d) => d.isCaughtUp);
}

/// Basic pay, and the dates that did or did not earn a day-credit.
class BasicBlock {
  final num amount;

  /// Only meaningful for an attendance-driven salary type. A monthly employee
  /// is paid the full basic regardless of days worked, and saying "8 days"
  /// there would explain something that did not happen.
  final bool attendanceDriven;
  final num? paidDays;
  final int creditedDays;
  final bool reconciles;
  final List<CreditedDay> days;

  const BasicBlock({
    required this.amount,
    required this.attendanceDriven,
    required this.paidDays,
    required this.creditedDays,
    required this.reconciles,
    required this.days,
  });

  factory BasicBlock.fromJson(Map<String, dynamic> j) => BasicBlock(
        amount: Money.asNum(j['amount']),
        attendanceDriven: _flag(j['attendance_driven']),
        paidDays: Money.toNum(j['paid_days']),
        creditedDays: _int(j['credited_days']),
        // Absent on an older payload means "nothing said it disagreed" — the
        // warning is for a server that actively reports a mismatch.
        reconciles: _flagTrue(j['reconciles']),
        days: ((j['days'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(CreditedDay.fromJson)
            .toList(growable: false),
      );

  /// "10 days worked" — the count as PAID, which the server derives from the
  /// payslip's own basic pay rather than from a re-count of attendance.
  String get paidDaysLabel {
    final d = paidDays;
    if (d == null) return '—';
    final whole = d == d.roundToDouble() ? d.round().toString() : d.toString();
    return '$whole day${d == 1 ? '' : 's'}';
  }
}

class CreditedDay {
  final String date;
  final String? status;
  final bool credited;
  final String? reason;

  const CreditedDay({required this.date, required this.status, required this.credited, required this.reason});

  factory CreditedDay.fromJson(Map<String, dynamic> j) => CreditedDay(
        date: '${j['date'] ?? ''}',
        status: j['status'] as String?,
        credited: _flag(j['credited']),
        reason: j['reason'] as String?,
      );

  /// A credited day states why it counted; an uncredited one states why it did
  /// not — that is the case an employee actually came here to look up.
  String get note => credited ? (reason ?? 'Counted as a day worked') : (reason ?? 'Not credited');
}

/// One side of the tardiness charge: what the payslip PAID, and what a rebuild
/// from today's attendance produces.
class TardinessTotal {
  final num paid;
  final num recomputed;
  final bool reconciles;

  const TardinessTotal({required this.paid, required this.recomputed, required this.reconciles});

  factory TardinessTotal.fromJson(Map<String, dynamic> j) => TardinessTotal(
        paid: Money.asNum(j['paid']),
        recomputed: Money.asNum(j['recomputed']),
        reconciles: _flagTrue(j['reconciles']),
      );
}

/// The leave exemption, in the words an employee would use.
///
/// A HALF-day no longer means "not charged": since the exemption was
/// re-anchored (2026-08-10) an approved AM half absorbs the morning and then
/// the ordinary grace runs from the midday boundary, so the same day can be
/// both covered AND charged. These labels name the COVER only — what it
/// absorbed, and what was left, are spelled out beside them.
const _coverLabel = <String, String>{
  'full': 'Approved leave — not charged',
  'am_half': 'Approved half-day (AM)',
  'pm_half': 'Approved half-day (PM)',
};

/// "1h 30m" / "45 min" — a duration in the words the payslip uses.
String minutesLabel(Object? total) {
  final n = _int(total);
  final h = n ~/ 60;
  final m = n % 60;
  if (h > 0 && m > 0) return '${h}h ${m}m';
  if (h > 0) return '${h}h';
  return '$m min';
}

/// One late/undertime day, in a sentence.
class DeductionDay {
  final String date;
  final int lateMinutes;
  final int undertimeMinutes;
  final String? leaveCover;
  final int leaveCoveredMinutes;
  final int? chargeableLateMinutes;
  final int? chargeableUndertimeMinutes;
  final num lateHours;
  final num lateAmount;
  final num undertimeHours;
  final num undertimeAmount;

  const DeductionDay({
    required this.date,
    required this.lateMinutes,
    required this.undertimeMinutes,
    required this.leaveCover,
    required this.leaveCoveredMinutes,
    required this.chargeableLateMinutes,
    required this.chargeableUndertimeMinutes,
    required this.lateHours,
    required this.lateAmount,
    required this.undertimeHours,
    required this.undertimeAmount,
  });

  factory DeductionDay.fromJson(Map<String, dynamic> j) => DeductionDay(
        date: '${j['date'] ?? ''}',
        lateMinutes: _int(j['late_minutes']),
        undertimeMinutes: _int(j['undertime_minutes']),
        leaveCover: j['leave_cover'] as String?,
        leaveCoveredMinutes: _int(j['leave_covered_minutes']),
        chargeableLateMinutes: _intOrNull(j['chargeable_late_minutes']),
        chargeableUndertimeMinutes: _intOrNull(j['chargeable_undertime_minutes']),
        lateHours: Money.asNum(j['late_hours']),
        lateAmount: Money.asNum(j['late_amount']),
        undertimeHours: Money.asNum(j['undertime_hours']),
        undertimeAmount: Money.asNum(j['undertime_amount']),
      );

  num get amount => lateAmount + undertimeAmount;

  static String _hours(num h) => '${h.toDouble().toStringAsFixed(2)} hour${h == 1 ? '' : 's'}';

  /// The hard case is a half-day leave that ALSO charges: the DTR says "316
  /// minutes late" (measured from the 9:00 start) while the payslip charges 16
  /// minutes (measured from the 2:00 PM boundary the leave moved the anchor
  /// to). Quoting either number alone leaves the employee unable to reconcile
  /// the two, so both are stated — what the leave absorbed, and what was
  /// charged after it.
  ///
  /// Falls back to the recorded minutes when the server predates the
  /// `chargeable_*` fields, so an older payload still renders a true sentence.
  String get note {
    if (leaveCover == 'full') return _coverLabel['full']!;

    final parts = <String>[];
    final cover = leaveCover;
    if (cover != null) {
      final label = _coverLabel[cover] ?? 'Approved half-day';
      parts.add(leaveCoveredMinutes > 0 ? '$label — ${minutesLabel(leaveCoveredMinutes)} covered' : label);
    }
    if (lateAmount > 0) {
      final mins = chargeableLateMinutes ?? lateMinutes;
      parts.add('${minutesLabel(mins)} late${cover != null ? ' after that' : ''} → ${_hours(lateHours)}');
    }
    if (undertimeAmount > 0) {
      final mins = chargeableUndertimeMinutes ?? undertimeMinutes;
      parts.add('${minutesLabel(mins)} early${cover != null ? ' before that' : ''} → ${_hours(undertimeHours)}');
    }
    // A covered day with nothing left to charge says so, rather than trailing off.
    if (cover != null && parts.length == 1) parts.add('nothing further charged');
    return parts.join(' · ');
  }
}

/// One approved overtime date, in a sentence.
///
/// Every approved date is listed, paid or NOT — a date that earned nothing is
/// the one an employee most needs explained, so showing only the paid ones
/// would hide exactly the case they came here to look up.
class OvertimeDay {
  final String date;
  final String? otType;
  final num hours;
  final num amount;
  final bool paid;
  final String? reason;
  final bool isCatchUp;
  final num? multiplier;
  final num? ratePerHour;

  const OvertimeDay({
    required this.date,
    required this.otType,
    required this.hours,
    required this.amount,
    required this.paid,
    required this.reason,
    required this.isCatchUp,
    required this.multiplier,
    required this.ratePerHour,
  });

  factory OvertimeDay.fromJson(Map<String, dynamic> j) => OvertimeDay(
        date: '${j['date'] ?? ''}',
        otType: j['ot_type'] as String?,
        hours: Money.asNum(j['hours']),
        amount: Money.asNum(j['amount']),
        paid: _flag(j['paid']),
        reason: j['reason'] as String?,
        isCatchUp: _flag(j['is_catch_up']),
        multiplier: Money.toNum(j['multiplier']),
        ratePerHour: Money.toNum(j['rate_per_hour']),
      );

  /// Overtime worked before this payslip's cutoff, paid here because the
  /// accomplishment report arrived after its own run had been computed. The
  /// SERVER marks it (`is_catch_up`, derived from `date < period_start`) rather
  /// than the client comparing dates: the payslip does not carry the run's
  /// period, and a reader working it out from the dates alone would be guessing.
  bool get isCaughtUp => paid && isCatchUp;

  /// A PAID date states the arithmetic that produced it — hours × the per-hour
  /// premium — because the amount on its own is exactly the figure people
  /// query. An UNPAID one states the server's reason instead, since overtime
  /// can be withheld for several different causes (converted to time-off, the
  /// clock-out fell short of the approved end, no accomplishment report) and
  /// only one of them is something the employee can still act on.
  String get note {
    if (!paid) return reason ?? 'Not paid';
    // A whole number of hours reads "3 hours", never "3.0 hours" — JavaScript's
    // Number() collapses the trailing zero and Dart's num does not, so the
    // website and the phone would otherwise word the same date differently.
    final whole = hours == hours.roundToDouble() ? hours.round().toString() : '$hours';
    final label = '$whole hour${hours == 1 ? '' : 's'}';
    final rate = ratePerHour;
    if (rate == null) return label;
    return '$label × ${Money.format(rate)} per hour';
  }
}
