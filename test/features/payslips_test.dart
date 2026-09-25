import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/format/money.dart';
import 'package:hris_mobile/core/http/api_exception.dart';
import 'package:hris_mobile/features/payslips/payslip_api.dart';
import 'package:hris_mobile/features/payslips/payslip_breakdown_models.dart';
import 'package:hris_mobile/features/payslips/payslip_detail_controller.dart';
import 'package:hris_mobile/features/payslips/payslip_detail_screen.dart';
import 'package:hris_mobile/features/payslips/payslip_models.dart';
import 'package:hris_mobile/features/payslips/payslips_controller.dart';
import 'package:hris_mobile/features/payslips/payslips_screen.dart';
import 'package:hris_mobile/shared/theme.dart';
import 'package:provider/provider.dart';

import '../fakes/payslip_fakes.dart';

Widget wrapList(PayslipsController c, PayslipApi api) => MultiProvider(
      providers: [
        Provider<PayslipApi?>.value(value: api),
        ChangeNotifierProvider<PayslipsController>.value(value: c),
      ],
      child: MaterialApp(
        theme: buildTheme(),
        home: const Scaffold(body: PayslipsScreen()),
      ),
    );

void main() {
  group('money', () {
    test('formats pesos the way the website does, and a missing value as a dash', () {
      expect(Money.format('12480.50'), '₱12,480.50');
      expect(Money.format(0), '₱0.00');
      expect(Money.format(null), '—');
      expect(Money.format(''), '—');
      expect(Money.format('not a number'), '—');
    });

    test('exactRate keeps the unrounded rate the arithmetic actually used', () {
      // 695 ÷ 8 = 86.875. Printed as ₱86.88 the reader computes
      // 86.88 × 1.10 = 95.57 while the payslip says 95.56.
      expect(Money.exactRate(86.875), '₱86.875');
      expect(Money.exactRate(100), '₱100');
      expect(Money.exactRate(null), '—');
    });
  });

  group('models', () {
    test('a payslip row parses DECIMAL strings and names its run', () {
      final p = PayslipSummary.fromJson(payslipRow(481));
      expect(p.id, 481);
      expect(p.netPay, 12480.50);
      expect(p.status, 'released');
      // payroll_runs.name is nullable, so the label falls back to the derived
      // "<Type> run · <period>" — the same name the website shows.
      expect(p.run!.displayName, 'Normal run · Aug 1, 2026 – Aug 15, 2026');
    });

    test('a named run keeps its own name', () {
      final p = PayslipSummary.fromJson(payslipRow(481, run: {
        'id': 7,
        'name': 'August 1st cut-off',
        'type': 'normal',
        'period_start': '2026-08-01',
        'period_end': '2026-08-15',
      }));
      expect(p.run!.displayName, 'August 1st cut-off');
    });

    test('a payslip whose run is gone still shows its money', () {
      final p = PayslipSummary.fromJson(payslipRow(481, run: null));
      expect(p.run, isNull);
      expect(p.netPay, 12480.50);
    });

    // Corrections HR files after finalizing (server 2026-09-25): the figure
    // shown is the ADJUSTED one, the original stays, and a server that never
    // sends the column still shows the right money.
    test('a list row pays the adjusted net and says so; an older server pays the original', () {
      final moved = PayslipSummary.fromJson(payslipRow(481, adjustedNetPay: '12980.50'));
      expect(moved.paidNet, 12980.50);
      expect(moved.netPay, 12480.50);
      expect(moved.isAdjusted, isTrue);

      final same = PayslipSummary.fromJson(payslipRow(481, adjustedNetPay: '12480.50'));
      expect(same.isAdjusted, isFalse);

      final old = PayslipSummary.fromJson(payslipRow(481));
      expect(old.adjustedNetPay, isNull);
      expect(old.paidNet, 12480.50);
      expect(old.isAdjusted, isFalse);
    });

    test('the detail carries the active adjustments and the net they make', () {
      final p = Payslip.fromJson(payslipDetail(
        481,
        adjustments: [
          adjustment(9, 'addition', 'earning', 'Missed OT', '500.00', reason: 'OT not captured'),
          adjustment(10, 'deduction', 'tax', 'Withholding tax on Missed OT', '75.00'),
        ],
        totals: {
          'payslip_id': 481,
          'original_net_pay': 12480.50,
          'adjustment_additions': 500,
          'adjustment_deductions': 75,
          'adjusted_net_pay': 12905.50,
        },
      ));
      expect(p.adjustments.length, 2);
      expect(p.adjustments.first.label, 'Missed OT');
      expect(p.adjustments.first.isDeduction, isFalse);
      expect(p.adjustments.last.isDeduction, isTrue);
      expect(p.adjustments.last.amount, 75);
      expect(p.paidNet, 12905.50);
      expect(p.netPay, 12480.50);
      expect(p.isAdjusted, isTrue);

      final old = Payslip.fromJson(payslipDetail(481));
      expect(old.adjustments, isEmpty);
      expect(old.paidNet, 12480.50);
      expect(old.isAdjusted, isFalse);
    });

    test('the detail carries only the EMPLOYEE share of the statutory columns', () {
      final p = Payslip.fromJson(payslipDetail(481));
      expect(p.sssEe, 675.00);
      expect(p.philhealthEe, 347.50);
      expect(p.pagibigEe, 100.00);
      expect(p.wht, 517.00);
      // The employer's share is not withheld from anybody's pay; the model has
      // no way to hold it.
      expect(p.toString().contains('1350'), isFalse);
    });

    test('line items group into the web category order, empty buckets dropped', () {
      final p = Payslip.fromJson(payslipDetail(481));
      expect(p.groupedItems.map((g) => g.category), ['earning', 'allowance', 'contribution', 'deduction', 'tax']);
      expect(p.groupedItems.first.label, 'Earnings');
      expect(p.groupedItems.first.items.length, 2);

      final sparse = Payslip.fromJson(payslipDetail(482, items: [item(1, 'tax', 'Withholding tax', '517.00')]));
      expect(sparse.groupedItems.map((g) => g.category), ['tax']);
    });

    test('a DATE renders as a calendar day, never shifted by a zone', () {
      expect(formatDateOnly('2026-08-01'), 'Aug 1, 2026');
      expect(formatShortDate('2026-08-06'), 'Aug 6');
      expect(formatDateOnly(null), '—');
    });
  });

  group('breakdown sentences', () {
    DeductionDay day(Map<String, dynamic> extra) => DeductionDay.fromJson({
          'date': '2026-08-07',
          'late_minutes': 0,
          'undertime_minutes': 0,
          'leave_cover': null,
          'leave_covered_minutes': 0,
          'chargeable_late_minutes': 0,
          'chargeable_undertime_minutes': 0,
          'late_hours': 0,
          'late_amount': 0,
          'undertime_hours': 0,
          'undertime_amount': 0,
          ...extra,
        });

    test('a full-day leave is not charged and says so', () {
      expect(day({'leave_cover': 'full'}).note, 'Approved leave — not charged');
    });

    test('a half-day that ALSO charges states both numbers', () {
      // The DTR says 316 minutes late (from the 9:00 start); the payslip charges
      // 16 (from the 2:00 PM boundary the leave moved the anchor to). Quoting
      // either alone leaves the employee unable to reconcile the two.
      final d = day({
        'leave_cover': 'am_half',
        'leave_covered_minutes': 300,
        'late_minutes': 316,
        'chargeable_late_minutes': 16,
        'late_hours': 0.27,
        'late_amount': 23.46,
      });
      expect(d.note, 'Approved half-day (AM) — 5h covered · 16 min late after that → 0.27 hours');
    });

    test('a covered day with nothing left to charge does not trail off', () {
      final d = day({'leave_cover': 'pm_half', 'leave_covered_minutes': 240});
      expect(d.note, 'Approved half-day (PM) — 4h covered · nothing further charged');
    });

    test('falls back to the recorded minutes when the server predates chargeable_*', () {
      final d = DeductionDay.fromJson({
        'date': '2026-08-04',
        'late_minutes': 16,
        'late_hours': 0.27,
        'late_amount': 23.46,
        'undertime_minutes': 0,
        'undertime_amount': 0,
        'undertime_hours': 0,
      });
      expect(d.note, '16 min late → 0.27 hours');
    });

    test('a paid overtime date states its arithmetic; an unpaid one states why', () {
      final paid = OvertimeDay.fromJson({
        'date': '2026-08-07',
        'hours': 3,
        'amount': 286.68,
        'paid': true,
        'rate_per_hour': 95.56,
        'multiplier': 1.1,
        'is_catch_up': false,
      });
      expect(paid.note, '3 hours × ₱95.56 per hour');
      expect(paid.isCaughtUp, isFalse);

      final unpaid = OvertimeDay.fromJson({
        'date': '2026-08-09',
        'hours': 2,
        'amount': 0,
        'paid': false,
        'reason': 'No accomplishment report submitted',
        'is_catch_up': false,
      });
      // The reason matters more than the zero: only some causes are still
      // something the employee can act on.
      expect(unpaid.note, 'No accomplishment report submitted');
    });

    test('a whole number of hours reads "3 hours", never "3.0 hours"', () {
      // JavaScript's Number() collapses the trailing zero; Dart's num does not.
      final d = OvertimeDay.fromJson({'date': '2026-08-07', 'hours': 3.0, 'amount': 286.68, 'paid': true, 'rate_per_hour': 95.56});
      expect(d.note, '3 hours × ₱95.56 per hour');
      final half = OvertimeDay.fromJson({'date': '2026-08-07', 'hours': 3.5, 'amount': 334.46, 'paid': true, 'rate_per_hour': 95.56});
      expect(half.note, '3.5 hours × ₱95.56 per hour');
    });

    test('an unpaid date is never tagged "earlier period", even when is_catch_up is set', () {
      final d = OvertimeDay.fromJson({'date': '2026-07-30', 'paid': false, 'is_catch_up': true, 'reason': 'Priced at zero'});
      expect(d.isCaughtUp, isFalse);
    });

    test('the payload parses, totals its overtime and quotes the rate once', () {
      final b = PayslipBreakdown.fromJson(breakdownPayload());
      expect(b.dailyRate, 695);
      expect(b.graceMinutes, 15);
      expect(b.overtimeTotal, 286.68);
      expect(b.ratedOvertimeDay!.ratePerHour, 95.56);
      expect(b.basic.paidDaysLabel, '20 days');
      expect(b.mismatched, isFalse);
      expect(b.hasDeductions, isTrue);
      expect(b.hasCatchUp, isFalse);
    });

    test('a server that reports a mismatch is believed', () {
      final b = PayslipBreakdown.fromJson(breakdownPayload(reconciles: false));
      expect(b.mismatched, isTrue);
    });

    // Captured verbatim from the sandbox (payslip 16391, sofia) so the parser is
    // pinned to what the server ACTUALLY sends, not to what the fakes assume —
    // note `daily_rate` arrives as a NUMBER while the payslip's money arrives as
    // DECIMAL strings.
    test('the real sandbox payload parses, mismatch and all', () {
      final b = PayslipBreakdown.fromJson(sandboxBreakdown);
      expect(b.dailyRate, 695);
      expect(b.hourlyRate, 86.875);
      expect(b.graceMinutes, 15);

      // Basic: 2 days paid, only 1 credited on today's attendance.
      expect(b.basic.paidDaysLabel, '2 days');
      expect(b.basic.days.map((d) => d.note), [
        'Counted as a day worked',
        'No time out recorded',
        'Absent — no time in',
      ]);

      // The payslip charged ₱23.46 of lateness; a rebuild produces ₱347.50.
      // They disagree, so the working must announce itself as stale rather than
      // quietly showing a second, different number.
      expect(b.mismatched, isTrue);
      expect(b.deductionsTotal, 23.46);
      expect(b.deductionDays.single.note, '3h 20m late → 4.00 hours');

      // Three approved overtime dates, one paid — and the two that paid nothing
      // each say WHY, which is the case an employee came here to look up.
      expect(b.overtimeTotal, 286.68);
      expect(b.overtimeDays.map((d) => d.note), [
        '3 hours × ₱95.56 per hour',
        'No clock-out on this date — approved overtime is paid only when it is worked',
        'No accomplishment report submitted',
      ]);
      expect(b.ratedOvertimeDay!.multiplier, 1.1);
      expect(b.hasCatchUp, isFalse);
    });
  });

  group('the list controller', () {
    test('loads page one, then APPENDS the next', () async {
      final api = FakePayslipApi(rows: [payslipRow(3), payslipRow(2), payslipRow(1)], totalPages: 3);
      final c = PayslipsController(api: api, pageSize: 1);

      await c.loadFirst();
      expect(c.items.length, 1);
      expect(c.loaded, isTrue);
      expect(c.hasMore, isTrue);

      await c.loadMore();
      expect(c.items.length, 2);
      expect(api.calls, ['list:1:1', 'list:2:1']);
    });

    test('a refresh replaces rather than doubling the rows', () async {
      final api = FakePayslipApi(rows: [payslipRow(3), payslipRow(2)], totalPages: 1);
      final c = PayslipsController(api: api, pageSize: 20);
      await c.loadFirst();
      await c.refresh();
      expect(c.items.length, 2);
    });

    test('no payslips is LOADED and empty, not an error', () async {
      final c = PayslipsController(api: FakePayslipApi());
      await c.loadFirst();
      expect(c.loaded, isTrue);
      expect(c.items, isEmpty);
      expect(c.error, isNull);
    });

    test('a failure surfaces the server message and leaves the list unloaded', () async {
      final api = FakePayslipApi()..listError = const ApiException(status: 500, message: 'Server error.');
      final c = PayslipsController(api: api);
      await c.loadFirst();
      expect(c.error, 'Server error.');
      expect(c.loaded, isFalse);
    });
  });

  group('the detail controller', () {
    test('loads the payslip and then its working', () async {
      final api = FakePayslipApi();
      final c = PayslipDetailController(api: api, payslipId: 481);
      await c.load();
      expect(c.state, PayslipLoadState.ready);
      expect(c.payslip!.netPay, 12480.50);
      expect(c.breakdown, isNotNull);
      expect(c.breakdownLoading, isFalse);
      expect(api.calls, ['detail:481', 'breakdown:481']);
    });

    test("a payslip that isn't mine is NOT FOUND, never an error", () async {
      // The server 404s rather than confirming another employee's payslip
      // exists; the screen must say "not found", as the website does.
      final api = FakePayslipApi()..detailError = notFound;
      final c = PayslipDetailController(api: api, payslipId: 999);
      await c.load();
      expect(c.state, PayslipLoadState.notFound);
      // And it never went on to ask for the working of a payslip it cannot read.
      expect(api.calls, ['detail:999']);
    });

    test('a breakdown that cannot be built is swallowed — the payslip still stands', () async {
      final api = FakePayslipApi()..breakdownError = const ApiException(status: 500, message: 'boom');
      final c = PayslipDetailController(api: api, payslipId: 481);
      await c.load();
      expect(c.state, PayslipLoadState.ready);
      expect(c.payslip, isNotNull);
      expect(c.breakdown, isNull);
      expect(c.breakdownLoading, isFalse);
    });
  });

  group('the screens', () {
    testWidgets('the list shows the run, the status and the net pay', (tester) async {
      final api = FakePayslipApi(rows: [payslipRow(481)]);
      final c = PayslipsController(api: api);
      await tester.pumpWidget(wrapList(c, api));
      await tester.pumpAndSettle();

      expect(find.text('1 payslip'), findsOneWidget);
      expect(find.text('Normal run · Aug 1, 2026 – Aug 15, 2026'), findsOneWidget);
      expect(find.text('Released'), findsOneWidget);
      expect(find.text('₱12,480.50'), findsOneWidget);
      expect(find.textContaining('#481'), findsOneWidget);
    });

    testWidgets('an account with no payslips gets the empty state, not an error', (tester) async {
      final api = FakePayslipApi();
      await tester.pumpWidget(wrapList(PayslipsController(api: api), api));
      await tester.pumpAndSettle();
      expect(find.text('No payslips yet'), findsOneWidget);
    });

    testWidgets('tapping a row opens that payslip', (tester) async {
      final api = FakePayslipApi(rows: [payslipRow(481)]);
      await tester.pumpWidget(wrapList(PayslipsController(api: api), api));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Normal run · Aug 1, 2026 – Aug 15, 2026'));
      await tester.pumpAndSettle();
      expect(find.text('Payslip #481'), findsOneWidget);
      expect(api.calls, contains('detail:481'));
    });

    testWidgets('the detail shows the figures, the statutory shares and the line items', (tester) async {
      final api = FakePayslipApi();
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: PayslipDetailScreen(payslipId: 481, api: api),
      ));
      await tester.pumpAndSettle();

      // The tile labels are the web's uppercase micro-label.
      expect(find.text('NET PAY'), findsWidgets);
      expect(find.text('₱12,480.50'), findsWidgets);
      expect(find.text('BASIC PAY'), findsOneWidget);

      // A lazy ListView never builds what is below the test viewport, so each
      // section below the fold is scrolled to before it is asserted on.
      await tester.scrollUntilVisible(find.text('Statutory contributions'), 300);
      expect(find.text('SSS'), findsWidgets);
      expect(find.text('₱517.00'), findsWidgets); // withholding tax

      await tester.scrollUntilVisible(find.text('Meal allowance'), 300);
      // "Basic pay" appears twice by then: the line item here, and the working's
      // own Basic pay block further down.
      expect(find.text('Basic pay'), findsWidgets);
      expect(find.text('Taxable'), findsOneWidget);
      // The employer's share is never drawn.
      expect(find.text('₱1,350.00'), findsNothing);
    });

    testWidgets('the working explains an uncredited day, the overtime rate and the grace', (tester) async {
      final api = FakePayslipApi();
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: PayslipDetailScreen(payslipId: 481, api: api),
      ));
      await tester.pumpAndSettle();

      // A lazy ListView never builds what is below the test viewport.
      await tester.scrollUntilVisible(find.text('How this was computed'), 300);
      await tester.pumpAndSettle();
      expect(find.text('No time out recorded'), findsOneWidget);

      await tester.scrollUntilVisible(find.textContaining('per overtime hour'), 300);
      expect(find.textContaining('₱86.875 per hour'), findsOneWidget);

      await tester.scrollUntilVisible(find.textContaining('is not charged'), 300);
      expect(find.textContaining('within 15 minutes'), findsOneWidget);
    });

    testWidgets('a stale working warns, and does not pretend to add up', (tester) async {
      final api = FakePayslipApi(breakdownJson: breakdownPayload(reconciles: false));
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: PayslipDetailScreen(payslipId: 481, api: api),
      ));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.textContaining('The payslip figures stand'), 300);
      expect(find.textContaining('The payslip figures stand'), findsOneWidget);
    });

    testWidgets('a breakdown that failed simply is not there', (tester) async {
      final api = FakePayslipApi()..breakdownError = const ApiException(status: 500, message: 'boom');
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: PayslipDetailScreen(payslipId: 481, api: api),
      ));
      await tester.pumpAndSettle();
      // …and the payslip above it is still fully readable.
      await tester.scrollUntilVisible(find.text('Statutory contributions'), 300);
      expect(find.text('Statutory contributions'), findsOneWidget);
      // Scrolled to the very bottom, there is no working and no apology for it.
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(find.text('How this was computed'), findsNothing);
      expect(find.textContaining('Working out the breakdown'), findsNothing);
    });

    testWidgets("someone else's payslip is 'not found', with no error styling", (tester) async {
      final api = FakePayslipApi()..detailError = notFound;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: PayslipDetailScreen(payslipId: 999, api: api),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Payslip not found'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    });
  });
}
