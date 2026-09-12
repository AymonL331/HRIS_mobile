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
        PageHeader(
          payslip.run?.displayName ?? 'Payslip #${payslip.id}',
          subtitle: payslip.transactionDate == null ? null : formatDateOnly(payslip.transactionDate),
        ),
        Padding(
          padding: const EdgeInsets.only(left: HrisSpace.s4, bottom: HrisSpace.s4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge(payslipStatusLabel(payslip.status), tone: payslipStatusTone(payslip.status)),
          ),
        ),

        // The one figure people open a payslip for.
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Net pay', padding: EdgeInsets.zero),
              const SizedBox(height: HrisSpace.s1),
              Text(
                Money.format(payslip.netPay),
                style: TextStyle(fontSize: HrisType.stat, fontWeight: HrisType.semibold, height: 1.15, color: t.text),
              ),
            ],
          ),
        ),
        const SizedBox(height: HrisSpace.s3),

        // The web's four tiles, two-up on a phone.
        Row(
          children: [
            Expanded(child: _Tile(label: 'Basic pay', value: payslip.basicPay)),
            const SizedBox(width: HrisSpace.s3),
            Expanded(child: _Tile(label: 'Total earnings', value: payslip.totalEarnings)),
          ],
        ),
        const SizedBox(height: HrisSpace.s3),
        Row(
          children: [
            Expanded(child: _Tile(label: 'Total deductions', value: payslip.totalDeductions)),
            const SizedBox(width: HrisSpace.s3),
            Expanded(child: _Tile(label: 'Net pay', value: payslip.netPay, accent: true)),
          ],
        ),
        const SizedBox(height: HrisSpace.s3),

        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Statutory contributions',
                style: TextStyle(fontSize: HrisType.md, fontWeight: HrisType.semibold, height: 1.35, color: t.text),
              ),
              const SizedBox(height: HrisSpace.s1),
              Text(
                'Your employee-share deductions for this pay period.',
                style: TextStyle(fontSize: HrisType.xs, height: 1.4, color: t.muted),
              ),
              const SizedBox(height: HrisSpace.s3),
              for (final (label, value) in statutory)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: HrisSpace.s1),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(label, style: TextStyle(fontSize: HrisType.sm, height: 1.4, color: t.muted)),
                      Text(
                        Money.format(value),
                        style: TextStyle(fontSize: HrisType.sm, fontWeight: HrisType.semibold, height: 1.4, color: t.text),
                      ),
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
                'Breakdown',
                style: TextStyle(fontSize: HrisType.md, fontWeight: HrisType.semibold, height: 1.35, color: t.text),
              ),
              const SizedBox(height: HrisSpace.s3),
              if (groups.isEmpty)
                Text(
                  'No line items were recorded for this payslip.',
                  style: TextStyle(fontSize: HrisType.xs, height: 1.4, color: t.muted),
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
                                Text(item.name, style: TextStyle(fontSize: HrisType.sm, height: 1.4, color: t.text)),
                                if (item.taxable) const StatusBadge('Taxable', tone: StatusTone.warning),
                              ],
                            ),
                          ),
                          const SizedBox(width: HrisSpace.s3),
                          Text(
                            Money.format(item.amount),
                            style: TextStyle(fontSize: HrisType.sm, fontWeight: HrisType.semibold, height: 1.4, color: t.text),
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
    return AppCard(
      padding: const EdgeInsets.all(HrisSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(label, padding: EdgeInsets.zero),
          const SizedBox(height: HrisSpace.s1),
          Text(
            Money.format(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: HrisType.lg,
              fontWeight: HrisType.semibold,
              height: 1.25,
              color: accent ? t.primary : t.text,
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
              Icon(icon, size: 40, color: t.muted),
              const SizedBox(height: HrisSpace.s3),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: HrisType.lg, fontWeight: HrisType.semibold, height: 1.3, color: t.text),
              ),
              const SizedBox(height: HrisSpace.s2),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: HrisType.sm, height: 1.5, color: t.muted),
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
        child: AppCard(
          tone: AppCardTone.danger,
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
