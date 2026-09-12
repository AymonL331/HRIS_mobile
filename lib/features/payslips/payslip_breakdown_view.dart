import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format/money.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/message_banner.dart';
import '../../shared/widgets/status_badge.dart';
import 'payslip_detail_controller.dart';
import 'payslip_models.dart';

/// "How this was computed" — the working behind a payslip, for the person whose
/// money it is. The web's PayslipBreakdown, on a phone.
///
/// Two questions, answered in the order people ask them:
///   1. Why is my basic ₱5,560 when I feel like I worked more days?
///      → the dates that earned a day-credit, and the ones that did not, with
///        the reason (absent · no time out).
///   2. Where did ₱1,042.50 of deductions come from?
///      → the contributing day, its minutes, the equivalent hours the company
///        ladder produced, and the peso amount.
///
/// A breakdown is SUPPORTING detail: when it cannot be built the controller
/// swallows the failure and this renders nothing, because the payslip above is
/// still correct and must still be readable.
class PayslipBreakdownView extends StatelessWidget {
  const PayslipBreakdownView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PayslipDetailController>();
    final t = HrisTokens.of(context);

    if (c.breakdownLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: HrisSpace.s3),
        child: Text(
          'Working out the breakdown…',
          style: TextStyle(fontSize: HrisType.xs, height: 1.4, color: t.muted),
        ),
      );
    }
    final b = c.breakdown;
    if (b == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: HrisSpace.s3),
          child: Text(
            'How this was computed',
            style: TextStyle(fontSize: HrisType.md, fontWeight: HrisType.semibold, height: 1.35, color: t.text),
          ),
        ),

        // The honest case: attendance changed after the run, so the rebuilt
        // figures no longer add up to what was paid. Say which is which.
        if (b.mismatched) ...[
          MessageBanner.warning(
            'These attendance records have changed since this payslip was computed, so the working below no '
            'longer adds up to the amounts paid. The payslip figures stand — they are what was paid.',
          ),
          const SizedBox(height: HrisSpace.s3),
        ],

        if (b.basic.attendanceDriven) ...[
          _Block(
            title: 'Basic pay',
            amount: b.basic.amount,
            formula: '${b.basic.paidDaysLabel} worked × ${Money.format(b.dailyRate)} per day',
            rows: [
              for (final d in b.basic.days)
                _DayRow(
                  date: d.date,
                  note: d.note,
                  amount: d.credited ? Money.format(b.dailyRate) : '—',
                  dimmed: !d.credited,
                ),
            ],
          ),
          const SizedBox(height: HrisSpace.s3),
        ],

        if (b.overtimeDays.isNotEmpty) ...[
          _Block(
            title: 'Overtime',
            amount: b.overtimeTotal,
            formula: b.ratedOvertimeDay == null
                ? 'No overtime was paid this period. Each date below says why.'
                : 'Paid at ${Money.exactRate(b.overtimeHourlyRate)} per hour × ${b.ratedOvertimeDay!.multiplier} '
                    '= ${Money.format(b.ratedOvertimeDay!.ratePerHour)} per overtime hour.',
            rows: [
              for (final d in b.overtimeDays)
                _DayRow(
                  date: d.date,
                  note: d.note,
                  amount: d.paid ? Money.format(d.amount) : '—',
                  dimmed: !d.paid,
                  // Marked on the DATE, because the date is what looks wrong: an
                  // employee scanning this list sees a day outside the cutoff
                  // they were paid for, and the tag answers the question that
                  // raises.
                  tag: d.isCaughtUp ? 'earlier period' : null,
                ),
            ],
            // Both money rules, said where the figure is being questioned.
            notes: [
              'Overtime is paid only for dates you clocked out at the approved end time, and only once you have '
                  'submitted the accomplishment report for that date.',
              // Shown only when it applies — a standing explanation of a rare
              // case would be noise on every other payslip.
              if (b.hasCatchUp)
                'Dates marked "earlier period" were worked before this payslip\'s cutoff. Their accomplishment '
                    'reports arrived after that period\'s payroll had already been computed, so the pay is '
                    'included here instead. Each date is paid once.',
            ],
          ),
          const SizedBox(height: HrisSpace.s3),
        ],

        if (b.hasDeductions)
          _Block(
            title: 'Late & undertime',
            amount: b.deductionsTotal,
            formula: 'Charged at ${Money.format(b.dailyRate)} ÷ 8 hours = ${Money.format(b.hourlyRate)} per hour. '
                'Arriving within ${b.graceMinutes} minutes of your start time is not charged.',
            rows: [
              for (final d in b.deductionDays)
                _DayRow(
                  date: d.date,
                  note: d.note,
                  amount: d.amount > 0 ? '− ${Money.format(d.amount)}' : Money.format(0),
                  dimmed: d.amount <= 0,
                ),
            ],
            // The rounding rule is the single most disputed part of the figure,
            // so it is stated rather than left to be discovered.
            notes: const [
              'Up to 30 minutes is charged by the minute. Past 30 minutes, any part of an hour is charged as a '
                  'whole hour.',
            ],
          ),
      ],
    );
  }
}

/// One explained figure: its title and amount, the formula that produced it,
/// the days behind it, and the rules worth stating.
class _Block extends StatelessWidget {
  final String title;
  final num amount;
  final String formula;
  final List<_DayRow> rows;
  final List<String> notes;

  const _Block({
    required this.title,
    required this.amount,
    required this.formula,
    required this.rows,
    this.notes = const [],
  });

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: HrisType.sm, fontWeight: HrisType.semibold, height: 1.35, color: t.text),
                ),
              ),
              Text(
                Money.format(amount),
                style: TextStyle(fontSize: HrisType.sm, fontWeight: HrisType.semibold, height: 1.35, color: t.text),
              ),
            ],
          ),
          const SizedBox(height: HrisSpace.s1),
          Text(formula, style: TextStyle(fontSize: HrisType.xs, height: 1.45, color: t.muted)),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: HrisSpace.s3),
            for (final row in rows) row,
          ],
          for (final note in notes) ...[
            const SizedBox(height: HrisSpace.s3),
            Text(note, style: TextStyle(fontSize: HrisType.xxs, height: 1.5, color: t.muted)),
          ],
        ],
      ),
    );
  }
}

/// One day of the working: the date, the sentence, and what it was worth.
class _DayRow extends StatelessWidget {
  final String date;
  final String note;
  final String amount;
  final bool dimmed;
  final String? tag;

  const _DayRow({required this.date, required this.note, required this.amount, this.dimmed = false, this.tag});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final labelColor = dimmed ? t.muted : t.text;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HrisSpace.s1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 58,
            child: Text(
              formatShortDate(date),
              style: TextStyle(fontSize: HrisType.xs, fontWeight: HrisType.semibold, height: 1.45, color: labelColor),
            ),
          ),
          const SizedBox(width: HrisSpace.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (tag != null) ...[
                  StatusBadge(tag!, tone: StatusTone.info),
                  const SizedBox(height: HrisSpace.s1),
                ],
                Text(note, style: TextStyle(fontSize: HrisType.xs, height: 1.45, color: t.muted)),
              ],
            ),
          ),
          const SizedBox(width: HrisSpace.s2),
          Text(
            amount,
            style: TextStyle(fontSize: HrisType.xs, fontWeight: HrisType.semibold, height: 1.45, color: labelColor),
          ),
        ],
      ),
    );
  }
}
