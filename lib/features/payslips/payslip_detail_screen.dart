import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format/money.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/message_banner.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/status_badge.dart';
import 'payslip_api.dart';
import 'payslip_breakdown_view.dart';
import 'payslip_detail_controller.dart';
import 'payslip_enums.dart';
import 'payslip_models.dart';

/// One payslip, in full — the web's MyPayslipDetailPage on a phone: the run it
/// belongs to, its status, the four figures, the statutory employee-share
/// contributions, the itemised lines grouped by category, and the working
/// behind it.
///
/// Pushed as its own route, so [api] arrives from the call site (the pushed
/// route sits above the shell's providers, and tests mount it with a fake).
class PayslipDetailScreen extends StatelessWidget {
  final int payslipId;
  final PayslipApi api;

  const PayslipDetailScreen({super.key, required this.payslipId, required this.api});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<PayslipDetailController>(
      create: (_) => PayslipDetailController(api: api, payslipId: payslipId)..load(),
      child: const _PayslipDetailView(),
    );
  }
}

class _PayslipDetailView extends StatelessWidget {
  const _PayslipDetailView();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PayslipDetailController>();
    return Scaffold(
      appBar: AppBar(title: Text('Payslip #${c.payslipId}')),
      body: switch (c.state) {
        PayslipLoadState.loading => const Center(child: CircularProgressIndicator()),
        // A payslip that isn't mine is a 404 on the server (it never confirms
        // another employee's payslip exists). Said as "not found", not as an
        // error — the same wording the website uses.
        PayslipLoadState.notFound => const _DetailEmpty(
            icon: Icons.search_off,
            title: 'Payslip not found',
            message: "This payslip may not exist or isn't yours. Go back to My Payslips.",
          ),
        PayslipLoadState.error => _DetailError(message: c.error ?? 'Please try again.', onRetry: c.load),
        PayslipLoadState.ready => c.payslip == null
            ? _DetailError(message: c.error ?? 'Please try again.', onRetry: c.load)
            : _PayslipBody(payslip: c.payslip!),
      },
    );
  }
}

class _PayslipBody extends StatelessWidget {
  final Payslip payslip;

  const _PayslipBody({required this.payslip});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);

    // Statutory EMPLOYEE-share contributions — what is withheld from the
    // employee. The employer's share is not withheld from anyone's pay and is
    // not shown here, exactly as on the website.
    final statutory = <(String, num)>[
      ('SSS', payslip.sssEe),
      ('PhilHealth', payslip.philhealthEe),
      ('Pag-IBIG', payslip.pagibigEe),
      ('Withholding tax', payslip.wht),
    ];
    final groups = payslip.groupedItems;

    return ListView(
      padding: const EdgeInsets.fromLTRB(HrisSpace.s4, 0, HrisSpace.s4, HrisSpace.s6),
      children: [
        // Aligned with the panels below it (the list already has the gutter).
        PageHeader(
          payslip.run?.displayName ?? 'Payslip #${payslip.id}',
          subtitle: payslip.transactionDate == null ? null : formatDateOnly(payslip.transactionDate),
          padding: const EdgeInsets.fromLTRB(0, HrisSpace.s4, 0, HrisSpace.s2),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: HrisSpace.s4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge(payslipStatusLabel(payslip.status), tone: payslipStatusTone(payslip.status)),
          ),
        ),

        // The one figure people open a payslip for. A correction HR filed after
        // finalizing moves it; the original stays readable under it, as on the web.
        // The web's net-pay box: petrol-soft fill, the figure in petrol.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(HrisSpace.s4),
          decoration: BoxDecoration(
            color: t.primarySoft,
            border: Border.all(color: t.primary.withValues(alpha: 0.25)),
            borderRadius: BorderRadius.circular(HrisRadius.panel),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                payslip.isAdjusted ? 'Adjusted net pay' : 'Net pay',
                style: TextStyle(fontSize: HrisType.sm, fontWeight: HrisType.medium, height: 20 / 14, color: t.text2),
              ),
              const SizedBox(height: 2),
              Text(
                Money.format(payslip.paidNet),
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: HrisType.semibold,
                  height: 36 / 28,
                  color: t.primaryText,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (payslip.isAdjusted)
                Text(
                  'Originally ${Money.format(payslip.netPay)}',
                  style: TextStyle(fontSize: HrisType.xs, height: 16 / 12, color: t.text2),
                ),
            ],
          ),
        ),
        const SizedBox(height: HrisSpace.s3),

        // The web's four figures: one panel, two-up, ruled between the cells.
        Container(
          decoration: BoxDecoration(
            color: t.surface,
            border: Border.all(color: t.border),
            borderRadius: BorderRadius.circular(HrisRadius.panel),
          ),
          child: Column(
            children: [
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _Tile(label: 'Basic pay', value: payslip.basicPay)),
                    VerticalDivider(width: 1, thickness: 1, color: t.border),
                    Expanded(child: _Tile(label: 'Total earnings', value: payslip.totalEarnings)),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: t.border),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _Tile(label: 'Total deductions', value: payslip.totalDeductions)),
                    VerticalDivider(width: 1, thickness: 1, color: t.border),
                    Expanded(child: _Tile(label: 'Net pay', value: payslip.netPay, accent: true)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: HrisSpace.s3),

        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Statutory contributions',
                style: TextStyle(fontSize: HrisType.md, fontWeight: HrisType.semibold, height: 24 / 16, color: t.text),
              ),
              const SizedBox(height: 2),
              Text(
                'Your employee-share deductions for this pay period.',
                style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text2),
              ),
              const SizedBox(height: HrisSpace.s2),
              // The web's ruled figure list: a rule under every line.
              for (final (label, value) in statutory)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.border))),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(label, style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text2)),
                      Text(
                        Money.format(value),
                        style: TextStyle(
                          fontSize: HrisType.sm,
                          fontWeight: HrisType.semibold,
                          height: 20 / 14,
                          color: t.text,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: HrisSpace.s3),

        // Corrections HR filed after this payslip was finalized. Only the
        // active ones arrive; they are paid with the payslip and make up the
        // adjusted net above.
        if (payslip.adjustments.isNotEmpty) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Adjustments',
                  style: TextStyle(fontSize: HrisType.md, fontWeight: HrisType.semibold, height: 24 / 16, color: t.text),
                ),
                const SizedBox(height: 2),
                Text(
                  'Corrections filed after this payslip was finalized. They are paid with it.',
                  style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text2),
                ),
                const SizedBox(height: HrisSpace.s2),
                for (final a in payslip.adjustments)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.border))),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.label, style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text)),
                              Text(
                                [payslipItemCategoryLabels[a.category] ?? a.category, if (a.reason != null && a.reason!.isNotEmpty) a.reason!].join(' · '),
                                style: TextStyle(fontSize: HrisType.xs, height: 16 / 12, color: t.text2),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: HrisSpace.s3),
                        Text(
                          '${a.isDeduction ? '−' : '+'}${Money.format(a.amount)}',
                          style: TextStyle(
                            fontSize: HrisType.sm,
                            fontWeight: HrisType.semibold,
                            height: 20 / 14,
                            color: a.isDeduction ? t.danger.text : t.text,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: HrisSpace.s3),
        ],

        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Breakdown',
                style: TextStyle(fontSize: HrisType.md, fontWeight: HrisType.semibold, height: 24 / 16, color: t.text),
              ),
              const SizedBox(height: HrisSpace.s3),
              if (groups.isEmpty)
                Text(
                  'No line items were recorded for this payslip.',
                  style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text2),
                )
              else
                for (final group in groups) ...[
                  SectionLabel(group.label, padding: const EdgeInsets.only(bottom: HrisSpace.s1)),
                  for (final item in group.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: HrisSpace.s1),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: HrisSpace.s2,
                              runSpacing: HrisSpace.s1,
                              children: [
                                Text(item.name, style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text)),
                                // A neutral tag, as the web's line item.
                                if (item.taxable) const StatusBadge('Taxable', tone: StatusTone.neutral),
                              ],
                            ),
                          ),
                          const SizedBox(width: HrisSpace.s3),
                          Text(
                            Money.format(item.amount),
                            style: TextStyle(
                              fontSize: HrisType.sm,
                              fontWeight: HrisType.semibold,
                              height: 20 / 14,
                              color: t.text,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: HrisSpace.s3),
                ],
            ],
          ),
        ),
        const SizedBox(height: HrisSpace.s3),

        // The working behind the two figures people query most.
        const PayslipBreakdownView(),
      ],
    );
  }
}

/// One of the four figure tiles.
class _Tile extends StatelessWidget {
  final String label;
  final num value;
  final bool accent;

  const _Tile({required this.label, required this.value, this.accent = false});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    // One cell of the figures panel (the panel draws the border and rules).
    return Padding(
      padding: const EdgeInsets.all(HrisSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: HrisType.xs, fontWeight: HrisType.medium, height: 16 / 12, color: t.text2)),
          const SizedBox(height: HrisSpace.s1),
          Text(
            Money.format(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: HrisType.md,
              fontWeight: HrisType.semibold,
              height: 24 / 16,
              color: accent ? t.primaryText : t.text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _DetailEmpty({required this.icon, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    // The web's EmptyState card; the icon stays, as a neutral gate mark.
    final t = HrisTokens.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(HrisSpace.s4),
        child: AppCard(
          maxWidth: 440,
          centered: true,
          padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s5, vertical: HrisSpace.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: t.neutral.bg, borderRadius: BorderRadius.circular(HrisRadius.control)),
                child: Icon(icon, size: 22, color: t.text2),
              ),
              const SizedBox(height: HrisSpace.s3),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: HrisType.md, fontWeight: HrisType.semibold, height: 24 / 16, color: t.text),
              ),
              const SizedBox(height: HrisSpace.s1),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _DetailError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(HrisSpace.s4),
        // A plain card with the error banner, as the web: one red element, not two.
        child: AppCard(
          maxWidth: 440,
          centered: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MessageBanner.error(message),
              const SizedBox(height: HrisSpace.s3),
              OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      ),
    );
  }
}
