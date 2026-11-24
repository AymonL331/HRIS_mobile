import 'package:flutter/material.dart';

import '../../core/format/money.dart';
import '../../core/http/api_exception.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/kit.dart';
import '../../shared/widgets/status_badge.dart';
import '../my_profile/web_format.dart';
import '../payslips/payslip_enums.dart';
import 'home_api.dart';
import 'home_models.dart';

/// HOME — the web self-service landing (pages/employee/EmployeeHomePage.jsx):
/// "Welcome, {username}" and four cards — My leave balance, My latest payslip,
/// My pending requests, Upcoming holidays. Every figure comes from
/// GET /api/me/dashboard; while it loads a spinner, on failure the error with
/// Try again, and each card an honest empty state rather than a zero.
class HomeScreen extends StatefulWidget {
  final HomeApi api;

  /// The signed-in login's username — the web greets `user.username`.
  final String username;

  /// Opens another destination: 'leave' (Manage my leave →), 'attendance'
  /// (My attendance →), 'payslips' when no [onOpenPayslip] is given.
  final ValueChanged<String>? onNavigate;

  /// View payslip → opens that payslip, as the web's /employee/payslips/:id.
  final ValueChanged<int>? onOpenPayslip;

  /// Whether this page is the one showing — the summary loads each time it is opened.
  final bool active;

  const HomeScreen({
    super.key,
    required this.api,
    required this.username,
    this.onNavigate,
    this.onOpenPayslip,
    this.active = true,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  MyDashboard? _summary;
  bool _loading = false;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    if (widget.active) _load();
  }

  @override
  void didUpdateWidget(HomeScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _load();
  }

  Future<void> _load() async {
    final id = ++_request; // a refetch is never overtaken by an older load
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await widget.api.dashboard();
      if (!mounted || id != _request) return;
      setState(() => _summary = s);
    } on ApiException catch (e) {
      if (!mounted || id != _request) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted || id != _request) return;
      setState(() => _error = 'Please try again.');
    } finally {
      if (mounted && id == _request) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final s = _summary;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s2, HrisSpace.s4, HrisSpace.s6),
        children: [
          Text(
            'Welcome, ${widget.username}',
            style: TextStyle(fontSize: HrisType.heading, height: 28 / 20, fontWeight: HrisType.semibold, color: t.text),
          ),
          Text('Your self-service home.', style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.muted)),
          const SizedBox(height: HrisSpace.s4),
          if (_loading && s == null) const SizedBox(height: 200, child: Center(child: LoadingBlock(semanticsLabel: 'Loading your summary'))),
          if (!_loading && _error != null)
            StatePanel(
              error: true,
              title: "Couldn't load your summary",
              message: _error,
              action: OutlinedButton(onPressed: _load, child: const Text('Try again')),
            ),
          if (s != null) ..._cards(s),
        ],
      ),
    );
  }

  List<Widget> _cards(MyDashboard s) {
    final leave = s.balances;
    final payslip = s.latestPayslip;
    final pending = s.pending;
    return [
      _HomeCard(
        title: 'My leave balance',
        children: [
          if (leave.isEmpty)
            _Empty('No leave balances set up for ${s.leaveYear} yet.')
          else ...[
            _Stat(numText(s.totalRemaining), 'days left'),
            _Kv([
              for (final b in leave)
                (b.leaveType, _Value(numText(b.remaining), suffix: 'of ${numText(b.accrued)}')),
            ]),
          ],
          _CardLink('Manage my leave →', () => widget.onNavigate?.call('leave')),
        ],
      ),
      _HomeCard(
        title: 'My latest payslip',
        children: [
          if (payslip == null)
            const _Empty('No payslip has been issued to you yet.')
          else ...[
            _Stat(Money.format(payslip.netPay), 'net pay'),
            _Kv([
              ('Period', _Value('${WebFormat.dateOnly(payslip.periodStart)} – ${WebFormat.dateOnly(payslip.periodEnd)}')),
              ('Status', StatusBadge(payslipStatusLabels[payslip.status] ?? payslip.status, tone: payslipStatusTone(payslip.status))),
            ]),
            _CardLink('View payslip →', () {
              if (widget.onOpenPayslip != null) {
                widget.onOpenPayslip!(payslip.id);
              } else {
                widget.onNavigate?.call('payslips');
              }
            }),
          ],
        ],
      ),
      _HomeCard(
        title: 'My pending requests',
        children: [
          if (pending.total == 0)
            const _Empty('Nothing awaiting approval.')
          else ...[
            _Stat('${pending.total}', 'awaiting approval'),
            _Kv([
              ('Leave', _Value('${pending.leave}')),
              ('DTR corrections', _Value('${pending.corrections}')),
              ('Travel orders', _Value('${pending.travelOrders}')),
            ]),
          ],
          _CardLink('My attendance →', () => widget.onNavigate?.call('attendance')),
        ],
      ),
      _HomeCard(
        title: 'Upcoming holidays',
        children: [
          if (s.holidays.isEmpty)
            const _Empty('No upcoming holidays on the company calendar.')
          else
            _Kv([for (final h in s.holidays) (h.title, _Value(WebFormat.dateOnly(h.date)))]),
        ],
      ),
    ];
  }
}

/// `.card`: surface, 1px border, radius 6, 20px padding; 16px title.
class _HomeCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _HomeCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: HrisSpace.s4),
      padding: const EdgeInsets.all(HrisSpace.s5),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(HrisRadius.panel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: HrisType.md, height: 24 / 16, fontWeight: HrisType.semibold, color: t.text)),
          const SizedBox(height: HrisSpace.s4),
          ...children,
        ],
      ),
    );
  }
}

/// `.stat` + `.statUnit`: the headline figure with its small muted unit.
class _Stat extends StatelessWidget {
  final String value;
  final String unit;

  const _Stat(this.value, this.unit);

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: HrisSpace.s4),
      child: Wrap(
        spacing: HrisSpace.s2,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: HrisType.stat,
              height: 32 / 24,
              fontWeight: HrisType.semibold,
              color: t.text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(unit, style: TextStyle(fontSize: HrisType.xs, color: t.muted)),
          ),
        ],
      ),
    );
  }
}

/// A `dd` value: semibold, with an optional muted normal-weight suffix ("of 15").
class _Value extends StatelessWidget {
  final String text;
  final String? suffix;

  const _Value(this.text, {this.suffix});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, fontWeight: HrisType.semibold, color: t.text),
        children: [
          TextSpan(text: text),
          if (suffix != null) TextSpan(text: ' $suffix', style: TextStyle(fontWeight: FontWeight.normal, color: t.muted)),
        ],
      ),
    );
  }
}

/// `.kv`: rows of label (muted 12) and value (semibold), each over a 1px rule.
class _Kv extends StatelessWidget {
  final List<(String, Widget)> rows;

  const _Kv(this.rows);

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: HrisSpace.s3),
          Container(
            padding: const EdgeInsets.only(bottom: HrisSpace.s2),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.border))),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: HrisSpace.s4,
              children: [
                Text(rows[i].$1, style: TextStyle(fontSize: HrisType.xs, height: 16 / 12, color: t.muted)),
                rows[i].$2,
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  final String text;

  const _Empty(this.text);

  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: HrisTokens.of(context).muted));
}

/// `.cardLink`: primary text, 14 semibold, 16px above.
class _CardLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _CardLink(this.label, this.onTap);

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: HrisSpace.s4),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: HrisSpace.s2),
          child: Text(label, style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, fontWeight: HrisType.semibold, color: t.primaryText)),
        ),
      ),
    );
  }
}
