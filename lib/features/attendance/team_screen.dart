import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/time/manila_time.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/message_banner.dart';
import '../../shared/widgets/status_badge.dart';
import 'team_controller.dart';
import 'team_models.dart';

/// Everyone's attendance for one day, read-only — the console DTR's calendar
/// view on a phone, for a login that holds attendance:view. Who is in, who is
/// late, who has no record, and whether a phone punch was in range. Drawn
/// like the web Records page: a toolbar bar, then the rows in a bordered card.
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
    final t = HrisTokens.of(context);

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
        // The toolbar: day picker (back / label / forward, never past today,
        // plus Today), on a surface bar with a hairline underneath.
        Container(
          decoration: BoxDecoration(color: t.surface, border: Border(bottom: BorderSide(color: t.border))),
          padding: const EdgeInsets.fromLTRB(HrisSpace.s2, HrisSpace.s1, HrisSpace.s2, HrisSpace.s1),
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
                    style: TextStyle(fontSize: HrisType.sm, fontWeight: HrisType.semibold, height: 1.35, color: t.text),
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
                TextButton(
                  onPressed: c.loading ? null : c.goToToday,
                  style: TextButton.styleFrom(foregroundColor: t.primary),
                  child: const Text('Today'),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s3, HrisSpace.s4, HrisSpace.s2),
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
            padding: const EdgeInsets.fromLTRB(HrisSpace.s4, 0, HrisSpace.s4, HrisSpace.s2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${c.total} employee${c.total == 1 ? '' : 's'} · $summary',
                style: TextStyle(fontSize: HrisType.xs, height: 1.4, color: t.muted),
              ),
            ),
          ),
        Expanded(child: _body(c, t)),
      ],
    );
  }

  Widget _body(TeamAttendanceController c, HrisTokens t) {
    if (!c.loadedOnce && c.loading) return const Center(child: CircularProgressIndicator());
    if (!c.loadedOnce && c.error != null) {
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
                OutlinedButton(onPressed: c.load, child: const Text('Try again')),
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
        // Pull works even when the page is short (nobody to show, or an error).
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (c.error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(HrisSpace.s4, 0, HrisSpace.s4, HrisSpace.s2),
                child: MessageBanner.warning(c.error!),
              ),
            ),
          if (c.loading) const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
          if (c.items.isEmpty && !c.loading)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(HrisSpace.s4),
                  child: AppCard(
                    maxWidth: 440,
                    padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s5, vertical: HrisSpace.s6),
                    child: Text(
                      c.search.trim().isEmpty ? 'No employees to show for this day.' : 'No employee matches "${c.search.trim()}".',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: HrisType.sm, height: 1.4, color: t.muted),
                    ),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s1, HrisSpace.s4, HrisSpace.s3),
              sliver: DecoratedSliver(
                decoration: cardDecoration,
                sliver: SliverList.separated(
                  itemCount: c.items.length,
                  itemBuilder: (_, i) => _PersonTile(day: c.items[i]),
                  separatorBuilder: (_, _) => Divider(height: 1, indent: HrisSpace.s4, color: t.border),
                ),
              ),
            ),
          if (c.hasMore)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s1, HrisSpace.s4, HrisSpace.s5),
                child: OutlinedButton.icon(
                  onPressed: c.loadingMore ? null : c.loadMore,
                  icon: c.loadingMore
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.expand_more),
                  label: Text('Load more (${c.items.length} of ${c.total})'),
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
    final t = HrisTokens.of(context);

    final badgeText = switch (day.dayType) {
      'worked' => day.status == 'late' ? 'Late' : day.status == 'official_business' ? 'OB' : 'Present',
      'absent' => 'Absent',
      'on_leave' => 'Leave',
      'holiday' => 'Holiday',
      'rest_day' => 'Rest day',
      _ => 'No record',
    };
    final badgeTone = dtrDayTone(day.dayType, day.status);

    final times = !day.hasPunch
        ? null
        : '${day.clockInAt == null ? '—' : ManilaTime.time(day.clockInAt!)}  →  ${day.clockOutAt == null ? '—' : ManilaTime.time(day.clockOutAt!)}';

    final chips = <(String, StatusTone)>[
      if (day.isLate && day.lateMinutes > 0) ('Late ${day.lateMinutes} min', StatusTone.warning),
      if (day.isUndertime && day.undertimeMinutes > 0) ('Undertime ${day.undertimeMinutes} min', StatusTone.warning),
      if (day.isHalfDay) ('Half day', StatusTone.info),
      if (day.leaveTypeName != null)
        ('${day.leaveTypeName}${day.leaveDayPart != null && day.leaveDayPart != 'full' ? ' (${day.leaveDayPart!.toUpperCase()})' : ''}', StatusTone.success),
      if (day.holidayTitle != null) (day.holidayTitle!, StatusTone.info),
      if (day.isMobilePunch) ('Mobile app', StatusTone.info),
      if (day.outOfRange) ('Out of range', StatusTone.danger),
      if (day.locationFlagged && !day.outOfRange) ('Flagged for HR', StatusTone.warning),
    ];

    final where = [
      if (day.inAddress != null && day.inAddress!.isNotEmpty) 'In: ${day.inAddress}',
      if (day.outAddress != null && day.outAddress!.isNotEmpty) 'Out: ${day.outAddress}',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s3, HrisSpace.s4, HrisSpace.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      day.employeeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: HrisType.sm, fontWeight: HrisType.semibold, height: 1.35, color: t.text),
                    ),
                    if (day.employeeCode != null)
                      Text(day.employeeCode!, style: TextStyle(fontSize: HrisType.xxs, fontWeight: HrisType.semibold, height: 1.3, color: t.muted)),
                  ],
                ),
              ),
              const SizedBox(width: HrisSpace.s2),
              StatusBadge(badgeText, tone: badgeTone),
            ],
          ),
          if (times != null) ...[
            const SizedBox(height: HrisSpace.s1 + 2),
            Row(
              children: [
                Text(times, style: TextStyle(fontSize: HrisType.sm, height: 1.4, color: t.text)),
                if (day.workedLabel.isNotEmpty) ...[
                  const Spacer(),
                  Text(day.workedLabel, style: TextStyle(fontSize: HrisType.xs, height: 1.4, color: t.muted)),
                ],
              ],
            ),
          ],
          if (where.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(where, style: TextStyle(fontSize: HrisType.xs, height: 1.4, color: t.muted), maxLines: 2, overflow: TextOverflow.ellipsis),
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
    );
  }
}
