import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/time/duration_label.dart';
import '../../core/time/manila_time.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/kit.dart';
import 'attendance_controller.dart';
import 'attendance_models.dart';

/// SUMMARY (2026-10-27) — the web My Attendance's Summary view: a Period choice,
/// the headline tiles (AttendanceSummaryCards: same metrics, same words, same
/// "show only when there is one" rule for half-days and flagged location), then
/// the months behind them. Every figure is the server's aggregate — nothing is
/// added up from the rows on the phone.
class AttendanceSummaryView extends StatefulWidget {
  const AttendanceSummaryView({super.key});

  @override
  State<AttendanceSummaryView> createState() => _AttendanceSummaryViewState();
}

class _AttendanceSummaryViewState extends State<AttendanceSummaryView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = context.read<AttendanceController>();
      if (c.summary == null && !c.summaryLoading) c.loadSummary();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AttendanceController>();
    final t = HrisTokens.of(context);
    final s = c.summary;

    return RefreshIndicator(
      onRefresh: c.loadSummary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s2, HrisSpace.s4, HrisSpace.s6),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 240,
              child: DropdownButtonFormField<SummaryPeriod>(
                initialValue: c.period,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Period'),
                items: [
                  for (final p in SummaryPeriod.values) DropdownMenuItem(value: p, child: Text(p.label)),
                ],
                onChanged: c.summaryLoading ? null : (p) => p == null ? null : c.setPeriod(p),
              ),
            ),
          ),
          const SizedBox(height: HrisSpace.s4),
          if (c.summaryLoading && s == null)
            const LoadingBlock(semanticsLabel: 'Loading your summary')
          else if (c.summaryError != null)
            StatePanel(
              error: true,
              title: "Couldn't load your summary",
              message: c.summaryError,
              action: OutlinedButton(onPressed: c.loadSummary, child: const Text('Try again')),
            )
          else if (s != null && s.totals.records == 0)
            // Zero records gets the empty state ALONE — a grid of zeros reads as data.
            const StatePanel(
              title: 'Nothing recorded in this period',
              message: 'Pick a wider period, or clock in — your days appear here as they are recorded.',
            )
          else if (s != null) ...[
            if (c.summaryLoading) ...[
              const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: HrisSpace.s2),
            ],
            SummaryTiles(totals: s.totals),
            if (s.months.isNotEmpty) ...[
              const SizedBox(height: HrisSpace.s5),
              Text(
                'Month by month',
                style: TextStyle(fontSize: HrisType.md, fontWeight: HrisType.semibold, height: 24 / 16, color: t.text),
              ),
              const SizedBox(height: HrisSpace.s2),
              RuledList(children: [for (final m in s.months) _MonthRow(m)]),
            ],
          ],
        ],
      ),
    );
  }
}

/// One tile of the web's summary grid.
class _Metric {
  final String label;
  final String value;
  final String hint;
  final StatusSet Function(HrisTokens t)? tone;
  const _Metric(this.label, this.value, this.hint, [this.tone]);
}

List<_Metric> _summaryMetrics(AttendanceTotals x) {
  String plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';
  return [
    _Metric(
      'Days recorded',
      '${x.records}',
      x.firstDate != null && x.lastDate != null
          ? '${ManilaTime.dateOnly(x.firstDate!)} – ${ManilaTime.dateOnly(x.lastDate!)}'
          : 'No records in range',
    ),
    _Metric('Present', '${x.presentDays}', x.obDays > 0 ? '+ ${x.obDays} official business' : 'Days marked present', (t) => t.success),
    _Metric('Late', '${x.lateDays}', x.lateMinutes > 0 ? '${hoursMinutes(x.lateMinutes)} total' : 'No lateness recorded', (t) => t.warning),
    _Metric('Absent', '${x.absentDays}', 'Days marked absent', (t) => t.danger),
    _Metric(
      'Total worked',
      hoursMinutes(x.workedMinutes),
      // Averaged over COMPLETE days (both punches) — said on the tile.
      x.avgWorkedMinutes == null ? 'No complete day yet' : '${hoursMinutes(x.avgWorkedMinutes!)} avg / complete day',
    ),
    _Metric(
      'Undertime',
      '${x.undertimeIncidents}',
      x.undertimeMinutes > 0 ? '${hoursMinutes(x.undertimeMinutes)} total' : 'No early departures',
      (t) => t.warning,
    ),
    // Exception counters: shown only when there is an exception.
    if (x.halfDays > 0) _Metric('Half-days', '${x.halfDays}', 'Complete days under a full day', (t) => t.info),
    _Metric('Missing clock-out', '${x.missingClockOut}', '${plural(x.openDays, 'day')} still open', (t) => t.danger),
    _Metric('Face clock', '${x.faceDays}', 'of ${plural(x.records, 'day')} recorded', (t) => t.info),
    if (x.flaggedDays > 0) _Metric('Flagged location', '${x.flaggedDays}', 'Out of geofence or low accuracy', (t) => t.warning),
  ];
}

/// The tiles, two to a row inside one bordered panel with 1px rules between —
/// the web grid at phone width.
class SummaryTiles extends StatelessWidget {
  final AttendanceTotals totals;
  const SummaryTiles({super.key, required this.totals});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final metrics = _summaryMetrics(totals);
    final rows = <List<_Metric>>[
      for (var i = 0; i < metrics.length; i += 2) metrics.sublist(i, (i + 2).clamp(0, metrics.length)),
    ];
    return RuledList(
      children: [
        for (final row in rows)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _Tile(row[0])),
                VerticalDivider(width: 1, thickness: 1, color: t.border),
                Expanded(child: row.length > 1 ? _Tile(row[1]) : const SizedBox.shrink()),
              ],
            ),
          ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final _Metric m;
  const _Tile(this.m);

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return Padding(
      padding: const EdgeInsets.all(HrisSpace.s3 + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (m.tone != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: m.tone!(t).solid, borderRadius: BorderRadius.circular(1)),
                ),
                const SizedBox(width: HrisSpace.s2),
              ],
              Flexible(
                child: Text(m.label, style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text2)),
              ),
            ],
          ),
          const SizedBox(height: HrisSpace.s1),
          Text(
            m.value,
            style: TextStyle(
              fontSize: HrisType.stat,
              fontWeight: HrisType.semibold,
              height: 32 / 24,
              color: t.text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(m.hint, style: TextStyle(fontSize: HrisType.xs, height: 16 / 12, color: t.text2)),
        ],
      ),
    );
  }
}

/// One month of the breakdown — the web table's row, folded for a phone: the
/// month, the day counts, then the time figures.
class _MonthRow extends StatelessWidget {
  final AttendanceTotals m;
  const _MonthRow(this.m);

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final counts = [
      '${m.records} days',
      '${m.presentDays} present',
      '${m.lateDays} late',
      '${m.absentDays} absent',
      if (m.obDays > 0) '${m.obDays} OB',
    ].join(' · ');
    final times = [
      'Worked ${hoursMinutes(m.workedMinutes)}',
      if (m.avgWorkedMinutes != null) 'avg ${hoursMinutes(m.avgWorkedMinutes!)}',
      if (m.lateMinutes > 0) 'late ${hoursMinutes(m.lateMinutes)}',
      if (m.undertimeMinutes > 0) 'undertime ${hoursMinutes(m.undertimeMinutes)}',
    ].join(' · ');
    return RuledRow(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            m.monthLabel.toUpperCase(),
            style: TextStyle(fontFamily: HrisFont.mono, fontSize: HrisType.sm, letterSpacing: 0.6, height: 20 / 14, color: t.text),
          ),
          const SizedBox(height: 2),
          Text(counts, style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text)),
          Text(times, style: TextStyle(fontSize: HrisType.xs, height: 18 / 12, color: t.text2)),
        ],
      ),
    );
  }
}
