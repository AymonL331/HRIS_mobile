import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/time/manila_time.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/message_banner.dart';
import '../../shared/widgets/status_badge.dart';
import 'attendance_controller.dart';
import 'attendance_models.dart';

/// My Attendance: the calendar-complete DTR, month by month, read-only. No
/// coordinates anywhere — the model does not even carry them. Drawn like the
/// web DTR: a month label, then the days as rows of a bordered card with the
/// web's status badges.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = context.read<AttendanceController>();
      if (c.isEmpty && !c.loading) c.loadCurrent();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AttendanceController>();
    final t = HrisTokens.of(context);
    if (c.isEmpty && c.loading) return const Center(child: CircularProgressIndicator());
    if (c.isEmpty && c.error != null) {
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
                OutlinedButton(onPressed: c.loadCurrent, child: const Text('Try again')),
              ],
            ),
          ),
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
          if (c.error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s2, HrisSpace.s4, 0),
                child: MessageBanner.warning(c.error!),
              ),
            ),
          for (final m in c.months) ...[
            SliverPersistentHeader(pinned: true, delegate: _MonthHeader(m, t)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(HrisSpace.s4, 0, HrisSpace.s4, HrisSpace.s3),
              sliver: DecoratedSliver(
                decoration: cardDecoration,
                sliver: m.days.isEmpty
                    ? SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(HrisSpace.s5),
                          child: Text(
                            'No days recorded for this month.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: HrisType.sm, height: 1.4, color: t.muted),
                          ),
                        ),
                      )
                    : SliverList.separated(
                        itemCount: m.days.length,
                        itemBuilder: (_, i) => _DayTile(day: m.days[i]),
                        separatorBuilder: (_, _) => Divider(height: 1, indent: 72, color: t.border),
                      ),
              ),
            ),
          ],
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s1, HrisSpace.s4, HrisSpace.s5),
              child: OutlinedButton.icon(
                onPressed: c.loading ? null : c.loadPrevious,
                icon: c.loading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.history),
                label: const Text('Load previous month'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The month label, pinned: the web section title with its muted summary,
/// on the page background.
class _MonthHeader extends SliverPersistentHeaderDelegate {
  final DtrMonth month;
  // The tokens in force are part of the delegate's identity: a pinned header
  // is not rebuilt for a theme change on its own, so a dark-mode switch would
  // leave it light.
  final HrisTokens t;
  _MonthHeader(this.month, this.t);

  @override
  double get minExtent => 56;
  @override
  double get maxExtent => 56;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final worked = month.count('worked');
    final absent = month.count('absent');
    final leave = month.count('on_leave');
    final summary = [
      '$worked worked',
      if (month.lateCount > 0) '${month.lateCount} late',
      if (absent > 0) '$absent absent',
      if (leave > 0) '$leave on leave',
    ].join(' · ');
    return SizedBox.expand(
      child: Container(
        color: t.bg,
        padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ManilaTime.monthLabel(month.year, month.month),
              style: TextStyle(fontSize: HrisType.md, fontWeight: HrisType.semibold, height: 1.35, color: t.text),
            ),
            Text(
              summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: HrisType.xs, height: 1.4, color: t.muted),
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _MonthHeader old) => old.month != month || old.t != t;
}

class _DayTile extends StatelessWidget {
  final DtrDay day;
  const _DayTile({required this.day});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final d = DateTime.tryParse(day.date);
    final dayNum = d == null ? '' : d.day.toString();
    final dow = d == null ? '' : ManilaTime.shortDate(day.date).split(',').first;

    final badgeText = switch (day.dayType) {
      'worked' => day.status == 'late' ? 'Late' : day.status == 'official_business' ? 'OB' : 'Present',
      'absent' => 'Absent',
      'on_leave' => 'Leave',
      'holiday' => 'Holiday',
      'rest_day' => 'Rest day',
      _ => 'No record',
    };
    final badgeTone = dtrDayTone(day.dayType, day.status);

    final times = day.clockInAt == null && day.clockOutAt == null
        ? null
        : '${day.clockInAt == null ? '—' : ManilaTime.time(day.clockInAt!)}  →  ${day.clockOutAt == null ? '—' : ManilaTime.time(day.clockOutAt!)}';

    final chips = <(String, StatusTone)>[
      if (day.isLate && day.lateMinutes > 0) ('Late ${day.lateMinutes} min', StatusTone.warning),
      if (day.isUndertime && day.undertimeMinutes > 0) ('Undertime ${day.undertimeMinutes} min', StatusTone.warning),
      if (day.isHalfDay) ('Half day', StatusTone.info),
      if (day.leaveTypeName != null)
        ('${day.leaveTypeName}${day.leaveDayPart != null && day.leaveDayPart != 'full' ? ' (${day.leaveDayPart!.toUpperCase()})' : ''}', StatusTone.success),
      if (day.holidayTitle != null) (day.holidayTitle!, StatusTone.info),
      if (day.captureMethod == 'mobile') ('Mobile app', StatusTone.info),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s3, HrisSpace.s4, HrisSpace.s3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                Text(dayNum, style: TextStyle(fontSize: HrisType.lg, fontWeight: HrisType.semibold, height: 1.2, color: t.text)),
                Text(dow, style: TextStyle(fontSize: HrisType.xxs, fontWeight: HrisType.semibold, height: 1.2, color: t.muted)),
              ],
            ),
          ),
          const SizedBox(width: HrisSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StatusBadge(badgeText, tone: badgeTone),
                    if (day.workedLabel.isNotEmpty) ...[
                      const Spacer(),
                      Text(day.workedLabel, style: TextStyle(fontSize: HrisType.xs, height: 1.4, color: t.muted)),
                    ],
                  ],
                ),
                if (times != null) ...[
                  const SizedBox(height: HrisSpace.s1 + 2),
                  Text(times, style: TextStyle(fontSize: HrisType.sm, height: 1.4, color: t.text)),
                ],
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: HrisSpace.s2),
                  Wrap(
                    spacing: HrisSpace.s1 + 2,
                    runSpacing: HrisSpace.s1,
                    children: [for (final (label, tone) in chips) StatusBadge(label, tone: tone)],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
