import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format/money.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/message_banner.dart';
import '../../shared/widgets/status_badge.dart';
import 'payslip_api.dart';
import 'payslip_detail_screen.dart';
import 'payslip_enums.dart';
import 'payslip_models.dart';
import 'payslips_controller.dart';

/// My Payslips — the employee's own payslips, newest first, read-only. Every
/// value is DB-backed through `GET /api/me/payslips`, which is ownership-scoped
/// on the server: this list can only ever be the signed-in employee's own.
///
/// The website pages with Previous/Next; here the rows accumulate and "Load
/// more" walks forward, which is what a phone list wants.
class PayslipsScreen extends StatefulWidget {
  const PayslipsScreen({super.key});

  @override
  State<PayslipsScreen> createState() => _PayslipsScreenState();
}

class _PayslipsScreenState extends State<PayslipsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = context.read<PayslipsController>();
      if (!c.loaded && !c.loading) c.loadFirst();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PayslipsController>();
    final t = HrisTokens.of(context);

    if (!c.loaded && c.loading) return const Center(child: CircularProgressIndicator());

    if (!c.loaded && c.error != null) {
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
                MessageBanner.error(c.error!),
                const SizedBox(height: HrisSpace.s3),
                OutlinedButton(onPressed: c.loadFirst, child: const Text('Try again')),
              ],
            ),
          ),
        ),
      );
    }

    if (c.items.isEmpty) {
      // Loaded and empty is not a failure — payroll simply has not run for this
      // employee yet. Same words as the web's EmptyState.
      return RefreshIndicator(
        onRefresh: c.refresh,
        child: ListView(
          padding: const EdgeInsets.all(HrisSpace.s4),
          children: [
            AppCard(
              maxWidth: 440,
              centered: true,
              padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s5, vertical: HrisSpace.s6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.receipt_long_outlined, size: 40, color: t.muted),
                  const SizedBox(height: HrisSpace.s3),
                  Text(
                    'No payslips yet',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: HrisType.lg, fontWeight: HrisType.semibold, height: 1.3, color: t.text),
                  ),
                  const SizedBox(height: HrisSpace.s2),
                  Text(
                    'Your payslips will appear here once payroll has been run for you.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: HrisType.sm, height: 1.5, color: t.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final cardDecoration = BoxDecoration(
      color: t.surface,
      border: Border.all(color: t.border),
      borderRadius: BorderRadius.circular(HrisRadius.md),
    );

    return RefreshIndicator(
      onRefresh: c.refresh,
      child: CustomScrollView(
        slivers: [
          // A page that failed AFTER rows are already on screen warns in place —
          // the rows above it are still true.
          if (c.error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s2, HrisSpace.s4, 0),
                child: MessageBanner.warning(c.error!),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s3, HrisSpace.s4, HrisSpace.s3),
              child: Text(
                '${c.total} payslip${c.total == 1 ? '' : 's'}',
                style: TextStyle(fontSize: HrisType.xs, height: 1.4, color: t.muted),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(HrisSpace.s4, 0, HrisSpace.s4, HrisSpace.s3),
            sliver: DecoratedSliver(
              decoration: cardDecoration,
              sliver: SliverList.separated(
                itemCount: c.items.length,
                itemBuilder: (_, i) => _PayslipTile(payslip: c.items[i]),
                separatorBuilder: (_, _) => Divider(height: 1, color: t.border),
              ),
            ),
          ),
          if (c.hasMore)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s1, HrisSpace.s4, HrisSpace.s5),
                child: OutlinedButton.icon(
                  onPressed: c.loading ? null : c.loadMore,
                  icon: c.loading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.expand_more),
                  label: const Text('Load more'),
                ),
              ),
            )
          else
            const SliverToBoxAdapter(child: SizedBox(height: HrisSpace.s5)),
        ],
      ),
    );
  }
}

class _PayslipTile extends StatelessWidget {
  final PayslipSummary payslip;

  const _PayslipTile({required this.payslip});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    // `payroll_runs.name` is nullable, so the run label falls back to the
    // derived "<Type> run · <period>" — the same name the admin surfaces and the
    // website use, so one payslip is identified identically everywhere.
    final runLabel = payslip.run?.displayName ?? 'Payslip #${payslip.id}';

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PayslipDetailScreen(
            payslipId: payslip.id,
            api: context.read<PayslipApi?>() ?? MobilePayslipApi(context.read()),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s3, HrisSpace.s3, HrisSpace.s3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    runLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: HrisType.sm, fontWeight: HrisType.semibold, height: 1.35, color: t.text),
                  ),
                  const SizedBox(height: HrisSpace.s1),
                  Row(
                    children: [
                      StatusBadge(payslipStatusLabel(payslip.status), tone: payslipStatusTone(payslip.status)),
                      const SizedBox(width: HrisSpace.s2),
                      Flexible(
                        child: Text(
                          '#${payslip.id}${payslip.transactionDate == null ? '' : ' · ${formatDateOnly(payslip.transactionDate)}'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: HrisType.xxs, height: 1.4, color: t.muted),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: HrisSpace.s3),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  Money.format(payslip.netPay),
                  style: TextStyle(fontSize: HrisType.md, fontWeight: HrisType.semibold, height: 1.3, color: t.text),
                ),
                Text('Net pay', style: TextStyle(fontSize: HrisType.xxs, height: 1.4, color: t.muted)),
              ],
            ),
            Icon(Icons.chevron_right, size: 20, color: t.muted),
          ],
        ),
      ),
    );
  }
}
