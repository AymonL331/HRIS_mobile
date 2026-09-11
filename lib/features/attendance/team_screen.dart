import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/time/manila_time.dart';
import '../../shared/widgets/message_banner.dart';
import 'team_controller.dart';
import 'team_models.dart';

/// Everyone's attendance for one day, read-only — the console DTR's calendar
/// view on a phone, for a login that holds attendance:view. Who is in, who is
/// late, who has no record, and whether a phone punch was in range.
class TeamAttendanceScreen extends StatefulWidget {
  const TeamAttendanceScreen({super.key});

  @override
  State<TeamAttendanceScreen> createState() => _TeamAttendanceScreenState();
}

class _TeamAttendanceScreenState extends State<TeamAttendanceScreen> {
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: context.read<TeamAttendanceController>().search);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = context.read<TeamAttendanceController>();
      if (!c.loadedOnce && !c.loading) c.load();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _pickDate(TeamAttendanceController c) async {
    final current = DateTime.tryParse(c.date) ?? DateTime.now();
    final last = DateTime.parse(c.today);
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isAfter(last) ? last : current,
      firstDate: DateTime(last.year - 2, 1, 1),
      lastDate: last,
      helpText: 'Attendance for',
    );
    if (picked == null) return;
    await c.setDate('${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<TeamAttendanceController>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final summary = c.loadedOnce && c.items.isNotEmpty
        ? [
            '${c.presentCount} present',
            if (c.lateCount > 0) '${c.lateCount} late',
            if (c.count('absent') > 0) '${c.count('absent')} absent',
            if (c.count('on_leave') > 0) '${c.count('on_leave')} on leave',
            if (c.count('no_record') > 0) '${c.count('no_record')} no record',
            if (c.outOfRangeCount > 0) '${c.outOfRangeCount} out of range',
          ].join(' · ')
        : null;

    return Column(
      children: [
        // Day picker: back / label / forward (never past today) + Today.
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Previous day',
                icon: const Icon(Icons.chevron_left),
                onPressed: c.loading ? null : c.previousDay,
              ),
              Expanded(
                child: TextButton(
                  onPressed: c.loading ? null : () => _pickDate(c),
                  child: Text(
                    ManilaTime.longDate(c.date),
                    textAlign: TextAlign.center,
                    style: text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next day',
                icon: const Icon(Icons.chevron_right),
                onPressed: c.loading || c.isToday ? null : c.nextDay,
              ),
              if (!c.isToday)
                TextButton(onPressed: c.loading ? null : c.goToToday, child: const Text('Today')),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: c.setSearch,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search name or employee code',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _search.clear();
                        c.setSearch('');
                      },
                    ),
            ),
          ),
        ),
        if (summary != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${c.total} employee${c.total == 1 ? '' : 's'} · $summary',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ),
        Expanded(child: _body(c)),
      ],
    );
  }

  Widget _body(TeamAttendanceController c) {
    if (!c.loadedOnce && c.loading) return const Center(child: CircularProgressIndicator());
    if (!c.loadedOnce && c.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MessageBanner.error(c.error!),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: c.load, child: const Text('Try again')),
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
              child: Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: MessageBanner.warning(c.error!)),
            ),
          if (c.loading)
            const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
          if (c.items.isEmpty && !c.loading)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    c.search.trim().isEmpty ? 'No employees to show for this day.' : 'No employee matches "${c.search.trim()}".',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          else
            SliverList.separated(
              itemCount: c.items.length,
              itemBuilder: (_, i) => _PersonTile(day: c.items[i]),
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
            ),
          if (c.hasMore)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: OutlinedButton.icon(
                  onPressed: c.loadingMore ? null : c.loadMore,
                  icon: c.loadingMore
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.expand_more),
                  label: Text('Load more (${c.items.length} of ${c.total})'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PersonTile extends StatelessWidget {
  final TeamDay day;
  const _PersonTile({required this.day});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final (badgeText, badgeColor) = switch (day.dayType) {
      'worked' => (
          day.status == 'late' ? 'Late' : day.status == 'official_business' ? 'OB' : 'Present',
          day.status == 'late' ? scheme.error : scheme.primary,
        ),
      'absent' => ('Absent', scheme.error),
      'on_leave' => ('Leave', scheme.tertiary),
      'holiday' => ('Holiday', scheme.secondary),
      'rest_day' => ('Rest day', scheme.outline),
      _ => ('No record', scheme.outline),
    };

    final times = !day.hasPunch
        ? null
        : '${day.clockInAt == null ? '—' : ManilaTime.time(day.clockInAt!)}  →  ${day.clockOutAt == null ? '—' : ManilaTime.time(day.clockOutAt!)}';

    final chips = <(String, Color?)>[
      if (day.isLate && day.lateMinutes > 0) ('Late ${day.lateMinutes} min', null),
      if (day.isUndertime && day.undertimeMinutes > 0) ('Undertime ${day.undertimeMinutes} min', null),
      if (day.isHalfDay) ('Half day', null),
      if (day.leaveTypeName != null)
        ('${day.leaveTypeName}${day.leaveDayPart != null && day.leaveDayPart != 'full' ? ' (${day.leaveDayPart!.toUpperCase()})' : ''}', null),
      if (day.holidayTitle != null) (day.holidayTitle!, null),
      if (day.isMobilePunch) ('Mobile app', null),
      if (day.outOfRange) ('Out of range', scheme.error),
      if (day.locationFlagged && !day.outOfRange) ('Flagged for HR', scheme.error),
    ];

    final where = [
      if (day.inAddress != null && day.inAddress!.isNotEmpty) 'In: ${day.inAddress}',
      if (day.outAddress != null && day.outAddress!.isNotEmpty) 'Out: ${day.outAddress}',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(day.employeeName, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (day.employeeCode != null)
                      Text(day.employeeCode!, style: text.labelSmall?.copyWith(color: scheme.outline)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(badgeText, style: text.labelMedium?.copyWith(color: badgeColor, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          if (times != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text(times, style: text.bodyMedium),
                if (day.workedLabel.isNotEmpty) ...[
                  const Spacer(),
                  Text(day.workedLabel, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ],
            ),
          ],
          if (where.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(where, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final (label, color) in chips)
                  Chip(
                    label: Text(label),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    labelStyle: text.labelSmall?.copyWith(color: color),
                    side: color == null ? null : BorderSide(color: color.withValues(alpha: 0.5)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
