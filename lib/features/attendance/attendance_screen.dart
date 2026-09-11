import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/time/manila_time.dart';
import '../../shared/widgets/message_banner.dart';
import 'attendance_controller.dart';
import 'attendance_models.dart';

/// My Attendance: the calendar-complete DTR, month by month, read-only. No
/// coordinates anywhere — the model does not even carry them.
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
    if (c.isEmpty && c.loading) return const Center(child: CircularProgressIndicator());
    if (c.isEmpty && c.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MessageBanner.error(c.error!),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: c.loadCurrent, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: c.refresh,
      child: CustomScrollView(
        slivers: [
          if (c.error != null)
            SliverToBoxAdapter(
              child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: MessageBanner.warning(c.error!)),
            ),
          for (final m in c.months) ...[
            SliverPersistentHeader(pinned: true, delegate: _MonthHeader(m)),
            if (m.days.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(padding: EdgeInsets.all(16), child: Text('No days recorded for this month.')),
              )
            else
              SliverList.separated(
                itemCount: m.days.length,
                itemBuilder: (_, i) => _DayTile(day: m.days[i]),
                separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
              ),
          ],
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton.icon(
                onPressed: c.loading ? null : c.loadPrevious,
                icon: c.loading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.history),
                label: const Text('Load previous month'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthHeader extends SliverPersistentHeaderDelegate {
  final DtrMonth month;
  _MonthHeader(this.month);

  @override
  double get minExtent => 56;
  @override
  double get maxExtent => 56;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final scheme = Theme.of(context).colorScheme;
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
      child: Material(
        color: scheme.surface,
        elevation: overlapsContent ? 1 : 0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ManilaTime.monthLabel(month.year, month.month), style: Theme.of(context).textTheme.titleMedium),
              Text(
                summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _MonthHeader old) => old.month != month;
}

class _DayTile extends StatelessWidget {
  final DtrDay day;
  const _DayTile({required this.day});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final d = DateTime.tryParse(day.date);
    final dayNum = d == null ? '' : d.day.toString();
    final dow = d == null ? '' : ManilaTime.shortDate(day.date).split(',').first;

    final (badgeText, badgeColor) = switch (day.dayType) {
      'worked' => (day.status == 'late' ? 'Late' : day.status == 'official_business' ? 'OB' : 'Present', day.status == 'late' ? scheme.error : scheme.primary),
      'absent' => ('Absent', scheme.error),
      'on_leave' => ('Leave', scheme.tertiary),
      'holiday' => ('Holiday', scheme.secondary),
      'rest_day' => ('Rest day', scheme.outline),
      _ => ('No record', scheme.outline),
    };

    final times = day.clockInAt == null && day.clockOutAt == null
        ? null
        : '${day.clockInAt == null ? '—' : ManilaTime.time(day.clockInAt!)}  →  ${day.clockOutAt == null ? '—' : ManilaTime.time(day.clockOutAt!)}';

    final chips = <String>[
      if (day.isLate && day.lateMinutes > 0) 'Late ${day.lateMinutes} min',
      if (day.isUndertime && day.undertimeMinutes > 0) 'Undertime ${day.undertimeMinutes} min',
      if (day.isHalfDay) 'Half day',
      if (day.leaveTypeName != null) '${day.leaveTypeName}${day.leaveDayPart != null && day.leaveDayPart != 'full' ? ' (${day.leaveDayPart!.toUpperCase()})' : ''}',
      if (day.holidayTitle != null) day.holidayTitle!,
      if (day.captureMethod == 'mobile') 'Mobile app',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                Text(dayNum, style: text.titleLarge),
                Text(dow, style: text.labelSmall?.copyWith(color: scheme.outline)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(badgeText, style: text.labelMedium?.copyWith(color: badgeColor, fontWeight: FontWeight.w600)),
                    ),
                    if (day.workedLabel.isNotEmpty) ...[
                      const Spacer(),
                      Text(day.workedLabel, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ],
                ),
                if (times != null) ...[
                  const SizedBox(height: 4),
                  Text(times, style: text.bodyMedium),
                ],
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final label in chips)
                        Chip(
                          label: Text(label),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          labelStyle: text.labelSmall,
                        ),
                    ],
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
