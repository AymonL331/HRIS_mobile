import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/http/api_exception.dart';
import '../../shared/button_styles.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/kit.dart';
import '../../shared/widgets/status_badge.dart';
import '../leave/leave_models.dart' show jsNumber;
import '../payslips/payslip_models.dart' show formatDateOnly;
import 'leave_calendar_api.dart';
import 'leave_calendar_models.dart';
import 'leave_calendar_month.dart';

/// LEAVE CALENDAR (2026-11-23) — the web portal's Leave Calendar on the phone
/// (pages/employee/LeaveCalendarPage.jsx → components/leave/LeaveCalendar.jsx):
/// Show (My leave / My branch / All employees — only what the SERVER offers),
/// Branch (two or more only), Employee (server search), the month with ‹ › Today,
/// the legend, the grid (holidays tint the day, leave chips, "+N more"), and the
/// day panel with everyone away that day. Never shows WHY anyone is away.
class LeaveCalendarScreen extends StatefulWidget {
  final LeaveCalendarApi api;

  /// Whether this page is the one showing. Loads on first opening.
  final bool active;

  /// "Today", for tests. Defaults to the phone's clock.
  final DateTime? today;

  const LeaveCalendarScreen({super.key, required this.api, this.active = true, this.today});

  @override
  State<LeaveCalendarScreen> createState() => _LeaveCalendarScreenState();
}

const _scopeLabels = {'self': 'My leave', 'branch': 'My branch', 'all': 'All employees'};
const _maxPerCell = 3;

class _LeaveCalendarScreenState extends State<LeaveCalendarScreen> {
  late MonthRef _month = MonthRef.of(widget.today);
  String _scope = 'all';
  String _branchId = '';
  String _employeeId = '';
  CalendarPerson? _employee;
  String? _selected;
  bool _hasLoaded = false;
  bool _started = false;

  LeaveCalendarData _data = LeaveCalendarData.empty;
  bool _loading = false;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    if (widget.active) _load();
  }

  @override
  void didUpdateWidget(LeaveCalendarScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _load();
  }

  ({String from, String to}) get _range => gridRange(_month);

  Future<void> _load() async {
    _started = true;
    final id = ++_requestId;
    final r = _range;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.get(scope: _scope, from: r.from, to: r.to, branchId: _branchId, employeeId: _employeeId);
      if (!mounted || id != _requestId) return;
      setState(() => _data = data);
      // The page opens on 'all'; an account the SERVER says doesn't have it is
      // stepped down to the widest scope it is offered (web: the same effect).
      if (_data.availableScopes[_scope] != true) {
        final widest = ['all', 'branch', 'self'].where((s) => _data.availableScopes[s] == true).firstOrNull;
        if (widest != null) {
          _scope = widest;
          unawaited(_load());
        }
      }
    } on ApiException catch (e) {
      // The previous month stays on screen behind the error.
      if (mounted && id == _requestId) setState(() => _error = e.message);
    } finally {
      if (mounted && id == _requestId) {
        setState(() {
          _loading = false;
          _hasLoaded = true;
        });
      }
    }
  }

  void _changeScope(String next) {
    setState(() {
      _scope = next;
      // A person — or a branch — picked under one scope may not exist under the next.
      _branchId = '';
      _employeeId = '';
      _employee = null;
    });
    _load();
  }

  void _changeBranch(String next) {
    setState(() {
      _branchId = next;
      _employeeId = '';
      _employee = null;
    });
    _load();
  }

  void _goToMonth(int delta) {
    setState(() {
      _month = _month.shift(delta);
      _selected = null;
    });
    _load();
  }

  void _today() {
    setState(() => _month = MonthRef.of(widget.today));
    _load();
  }

  Future<void> _pickEmployee() async {
    final picked = await showModalBottomSheet<_PickResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EmployeePickerSheet(api: widget.api, scope: _scope, branchId: _branchId, selectedId: _employeeId),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _employee = picked.person;
      _employeeId = picked.person == null ? '' : '${picked.person!.id}';
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final subtitle = Text(
      'Who is away and when — pending and approved leave, with the holidays that apply to your branch.',
      style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.muted),
    );

    Widget body;
    if (!_hasLoaded && (_loading || !_started)) {
      body = const LoadingBlock(semanticsLabel: 'Loading leave calendar');
    } else if (_error != null && _data.leaves.isEmpty && _data.holidays.isEmpty) {
      body = StatePanel(
        title: 'Something went wrong',
        message: _error,
        error: true,
        action: OutlinedButton(onPressed: _load, child: const Text('Try again')),
      );
    } else {
      body = _calendar(context);
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s2, HrisSpace.s4, HrisSpace.s6),
        children: [subtitle, const SizedBox(height: HrisSpace.s5), body],
      ),
    );
  }

  Widget _calendar(BuildContext context) {
    final t = HrisTokens.of(context);
    final r = _range;
    final byDay = indexByDay(_data, r.from, r.to);
    final todayKey = toDateKey(widget.today ?? DateTime.now());
    final total = _data.leaves.length;
    final locked = _scope == 'self';
    final showBranch = !locked && _data.availableBranches.length > 1;
    final options = _scopeLabels.entries.where((e) => _data.availableScopes[e.key] == true).toList();
    final labelStyle = TextStyle(fontSize: HrisType.sm, fontWeight: HrisType.medium, color: t.text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Filters: which population → which branch → which person.
        Text('Show', style: labelStyle),
        const SizedBox(height: HrisSpace.s1),
        if (options.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              key: const Key('leave_calendar_scope'),
              showSelectedIcon: false,
              segments: [for (final o in options) ButtonSegment(value: o.key, label: Text(o.value))],
              selected: {_scope},
              onSelectionChanged: (s) => _changeScope(s.first),
            ),
          ),
        if (showBranch) ...[
          const SizedBox(height: HrisSpace.s4),
          DropdownButtonFormField<String>(
            key: ValueKey('leave_calendar_branch_$_branchId'),
            initialValue: _branchId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Branch', floatingLabelBehavior: FloatingLabelBehavior.always),
            items: [
              DropdownMenuItem(value: '', child: Text('All branches', style: TextStyle(color: t.muted))),
              for (final b in _data.availableBranches)
                DropdownMenuItem(value: '${b.id}', child: Text(b.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => _changeBranch(v ?? ''),
          ),
        ],
        const SizedBox(height: HrisSpace.s4),
        InkWell(
          key: const Key('leave_calendar_employee'),
          onTap: locked ? null : _pickEmployee,
          borderRadius: BorderRadius.circular(HrisRadius.control),
          child: InputDecorator(
            isEmpty: _employee == null,
            decoration: InputDecoration(
              labelText: 'Employee',
              enabled: !locked,
              floatingLabelBehavior: FloatingLabelBehavior.always,
              suffixIcon: const Icon(Icons.expand_more),
            ),
            child: Text(
              locked ? 'Only me' : (_employee?.label ?? 'Everyone — or search a name'),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: HrisType.md, color: _employee == null || locked ? t.muted : t.text),
            ),
          ),
        ),
        const SizedBox(height: HrisSpace.s4),

        // Month bar.
        Row(
          children: [
            _NavButton(label: '‹', semantics: 'Previous month', onTap: () => _goToMonth(-1)),
            Expanded(
              child: Text(
                _month.label,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: HrisType.md, fontWeight: HrisType.semibold, color: t.text),
              ),
            ),
            _NavButton(label: '›', semantics: 'Next month', onTap: () => _goToMonth(1)),
            const SizedBox(width: HrisSpace.s2),
            TextButton(onPressed: _today, child: const Text('Today')),
          ],
        ),
        const SizedBox(height: HrisSpace.s2),
        Text(
          _loading
              ? 'Updating…'
              : total == 0
                  ? 'No leave filed for this period.'
                  : '$total leave record${total == 1 ? '' : 's'} this period',
          style: TextStyle(fontSize: HrisType.sm, color: t.muted),
        ),
        const SizedBox(height: HrisSpace.s4),

        // Legend.
        Wrap(
          spacing: HrisSpace.s4,
          runSpacing: HrisSpace.s2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _LegendKey(color: t.success.solid, label: 'Approved'),
            _LegendKey(color: t.warning.solid, label: 'Pending'),
            _LegendKey(color: t.info.solid, label: 'Holiday'),
            Text('Rejected and cancelled leave is not shown.',
                style: TextStyle(fontSize: HrisType.xs, fontStyle: FontStyle.italic, color: t.muted)),
          ],
        ),
        if (_data.truncated) ...[
          const SizedBox(height: HrisSpace.s4),
          Container(
            padding: const EdgeInsets.all(HrisSpace.s3),
            decoration: BoxDecoration(
              color: t.warning.bg,
              border: Border.all(color: t.warning.border),
              borderRadius: BorderRadius.circular(HrisRadius.control),
            ),
            child: Text(
              'This period has more records than the calendar can show at once. Narrow the view with the filters above to see them all.',
              style: TextStyle(fontSize: HrisType.sm, color: t.warning.text),
            ),
          ),
        ],
        const SizedBox(height: HrisSpace.s4),
        _MonthGrid(
          month: _month,
          byDay: byDay,
          selected: _selected,
          todayKey: todayKey,
          onSelect: (k) => setState(() => _selected = _selected == k ? null : k),
        ),
        const SizedBox(height: HrisSpace.s4),
        _DayPanel(date: _selected, entries: _selected == null ? null : byDay[_selected]),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  final String label;
  final String semantics;
  final VoidCallback onTap;

  const _NavButton({required this.label, required this.semantics, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        label: semantics,
        button: true,
        excludeSemantics: true,
        child: FilledButton(
          style: HrisButtonStyles.secondary(context, minHeight: 36).copyWith(
            padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: HrisSpace.s3)),
            minimumSize: const WidgetStatePropertyAll(Size(44, 36)),
          ),
          onPressed: onTap,
          child: Text(label, style: const TextStyle(fontSize: HrisType.md)),
        ),
      );
}

class _LegendKey extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendKey({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(HrisRadius.badge))),
        const SizedBox(width: HrisSpace.s2),
        Text(label, style: TextStyle(fontSize: HrisType.xs, color: t.muted)),
      ],
    );
  }
}

/// LeaveCalendarGrid at the web's phone width (≤ 640px): 78px cells, leave chips
/// shown as their status dot (the name is hidden there), holiday title chips,
/// "+N more"; the day panel below lists everything.
class _MonthGrid extends StatelessWidget {
  final MonthRef month;
  final Map<String, DayEntries> byDay;
  final String? selected;
  final String todayKey;
  final ValueChanged<String> onSelect;

  const _MonthGrid({
    required this.month,
    required this.byDay,
    required this.selected,
    required this.todayKey,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final cells = buildMonthGrid(month);
    final weeks = <List<MonthCell>>[];
    for (var i = 0; i < cells.length; i += 7) {
      weeks.add(cells.sublist(i, i + 7));
    }
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(HrisRadius.panel),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(HrisRadius.panel - 1),
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(color: t.bg, border: Border(bottom: BorderSide(color: t.border))),
              child: Row(
                children: [
                  for (final d in weekdayLabels)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(HrisSpace.s2),
                        child: Text(d,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, fontWeight: HrisType.semibold, color: t.muted)),
                      ),
                    ),
                ],
              ),
            ),
            for (var w = 0; w < weeks.length; w++)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: _DayCell(
                          cell: weeks[w][i],
                          entries: byDay[weeks[w][i].key],
                          selected: weeks[w][i].key == selected,
                          today: weeks[w][i].key == todayKey,
                          lastColumn: i == 6,
                          lastRow: w == weeks.length - 1,
                          onTap: () => onSelect(weeks[w][i].key),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final MonthCell cell;
  final DayEntries? entries;
  final bool selected;
  final bool today;
  final bool lastColumn;
  final bool lastRow;
  final VoidCallback onTap;

  const _DayCell({
    required this.cell,
    required this.entries,
    required this.selected,
    required this.today,
    required this.lastColumn,
    required this.lastRow,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final leaves = entries?.leaves ?? const <CalendarLeave>[];
    final holidays = entries?.holidays ?? const <CalendarHoliday>[];
    final shown = leaves.take(_maxPerCell).toList();
    final hidden = leaves.length - shown.length;
    // Order as the web's class list: outside → holiday tint → selected wins.
    var bg = cell.inMonth ? t.surface : t.bg;
    if (holidays.isNotEmpty) bg = t.info.bg;
    if (selected) bg = t.primarySoft;
    final dayColor = today ? t.primaryContrast : (!cell.inMonth || cell.restDay ? t.muted : t.text);

    return Semantics(
      button: true,
      selected: selected,
      label: '${cell.key}: ${leaves.length} on leave${holidays.isEmpty ? '' : ', ${holidays.map((h) => h.title).join(', ')}'}',
      excludeSemantics: true,
      child: Material(
        color: bg,
        child: InkWell(
          key: Key('leave_day_${cell.key}'),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 78),
            padding: const EdgeInsets.all(HrisSpace.s1),
            decoration: BoxDecoration(
              border: Border(
                right: lastColumn ? BorderSide.none : BorderSide(color: t.border),
                bottom: lastRow ? BorderSide.none : BorderSide(color: t.border),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                    alignment: Alignment.center,
                    decoration: today
                        ? BoxDecoration(color: t.primary, borderRadius: BorderRadius.circular(HrisRadius.badge))
                        : null,
                    child: Text('${cell.day}',
                        style: TextStyle(fontSize: HrisType.xs, fontWeight: HrisType.semibold, color: dayColor)),
                  ),
                ),
                for (final h in holidays) ...[
                  const SizedBox(height: HrisSpace.s1),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(
                      color: t.info.bg,
                      border: Border.all(color: t.info.border),
                      borderRadius: BorderRadius.circular(HrisRadius.control),
                    ),
                    child: Text(h.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: t.info.text)),
                  ),
                ],
                if (shown.isNotEmpty) ...[
                  const SizedBox(height: HrisSpace.s1),
                  Wrap(
                    spacing: 2,
                    runSpacing: 2,
                    children: [for (final l in shown) _LeaveChip(leave: l)],
                  ),
                ],
                if (hidden > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('+$hidden more', style: TextStyle(fontSize: 10, color: t.muted)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A leave in a cell, at phone width: the status tone with its dot. The reader's
/// own leave is outlined in petrol (the web marks it with weight and an inset
/// line; a coloured side stripe is not used in this app).
class _LeaveChip extends StatelessWidget {
  final CalendarLeave leave;

  const _LeaveChip({required this.leave});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final s = leave.status == 'pending' ? t.warning : t.success;
    return Tooltip(
      message: '${leave.employeeName} · ${leave.leaveTypeName ?? 'Leave'} · ${leave.status}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: s.bg,
          border: Border.all(color: leave.isSelf ? t.primary : s.border, width: leave.isSelf ? 1.5 : 1),
          borderRadius: BorderRadius.circular(HrisRadius.control),
        ),
        child: Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: s.solid, borderRadius: BorderRadius.circular(HrisRadius.badge)),
        ),
      ),
    );
  }
}

/// LeaveDayPanel — the picked day in full: every holiday and every leave on it,
/// who · what kind · how long · which state, never why.
class _DayPanel extends StatelessWidget {
  final String? date;
  final DayEntries? entries;

  const _DayPanel({required this.date, required this.entries});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final meta = TextStyle(fontSize: HrisType.xs, height: 16 / 12, color: t.muted);
    final placeholder = TextStyle(fontSize: HrisType.sm, color: t.muted);
    final box = BoxDecoration(
      color: t.surface,
      border: Border.all(color: t.border),
      borderRadius: BorderRadius.circular(HrisRadius.panel),
    );
    if (date == null) {
      return Container(
        padding: const EdgeInsets.all(HrisSpace.s4),
        decoration: box,
        child: Text('Select a day to see who is away.', style: placeholder),
      );
    }
    final leaves = entries?.leaves ?? const <CalendarLeave>[];
    final holidays = entries?.holidays ?? const <CalendarHoliday>[];
    return Container(
      padding: const EdgeInsets.all(HrisSpace.s4),
      decoration: box,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(formatDateOnly(date),
              style: TextStyle(fontSize: HrisType.md, fontWeight: HrisType.semibold, color: t.text)),
          const SizedBox(height: HrisSpace.s3),
          for (final h in holidays)
            Container(
              margin: const EdgeInsets.only(bottom: HrisSpace.s3),
              padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s3, vertical: HrisSpace.s2),
              decoration: BoxDecoration(
                color: t.info.bg,
                border: Border.all(color: t.info.border),
                borderRadius: BorderRadius.circular(HrisRadius.control),
              ),
              child: Wrap(
                spacing: HrisSpace.s2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(h.title, style: TextStyle(fontWeight: HrisType.semibold, color: t.info.text)),
                  Text('${h.typeLabel} · ${h.whereLabel}', style: meta),
                ],
              ),
            ),
          if (leaves.isEmpty && holidays.isEmpty) Text('Nobody is on leave this day.', style: placeholder),
          for (var i = 0; i < leaves.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: HrisSpace.s3),
              decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: t.border))),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(TextSpan(
                          text: leaves[i].employeeName,
                          style: TextStyle(fontWeight: HrisType.semibold, color: t.text),
                          children: [
                            if (leaves[i].isSelf)
                              TextSpan(text: ' (you)', style: TextStyle(fontWeight: FontWeight.w400, color: t.muted)),
                          ],
                        )),
                        Text(
                          [leaves[i].employeeCode, leaves[i].branchName].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                          style: meta,
                        ),
                        const SizedBox(height: HrisSpace.s1),
                        Text(leaves[i].leaveTypeName ?? 'Leave', style: TextStyle(fontSize: HrisType.sm, color: t.text)),
                        Text(_span(leaves[i]), style: meta),
                      ],
                    ),
                  ),
                  const SizedBox(width: HrisSpace.s3),
                  StatusBadge(
                    leaves[i].status == 'approved' ? 'Approved' : 'Pending',
                    tone: leaves[i].status == 'approved' ? StatusTone.success : StatusTone.warning,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _span(CalendarLeave l) {
    final when = l.dateFrom == l.dateTo
        ? formatDateOnly(l.dateFrom)
        : '${formatDateOnly(l.dateFrom)} – ${formatDateOnly(l.dateTo)}';
    final d = l.days == null || '${l.days}'.isEmpty ? null : jsNumber(l.days);
    if (d == null || d == '0' || d == 'NaN') return when;
    return '$when · $d day${d == '1' ? '' : 's'}';
  }
}

class _PickResult {
  final CalendarPerson? person;

  const _PickResult(this.person);
}

/// The web SearchableSelect for "Employee": a search box over the SERVER's
/// capped list (debounced 350 ms), "Everyone" to clear, and the truncation hint.
class _EmployeePickerSheet extends StatefulWidget {
  final LeaveCalendarApi api;
  final String scope;
  final String branchId;
  final String selectedId;

  const _EmployeePickerSheet({required this.api, required this.scope, required this.branchId, required this.selectedId});

  @override
  State<_EmployeePickerSheet> createState() => _EmployeePickerSheetState();
}

class _EmployeePickerSheetState extends State<_EmployeePickerSheet> {
  final _search = TextEditingController();
  Timer? _debounce;
  CalendarPeople _people = const CalendarPeople();
  bool _loading = true;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load(String q) async {
    final id = ++_requestId;
    setState(() => _loading = true);
    try {
      final p = await widget.api.people(scope: widget.scope, branchId: widget.branchId, search: q);
      if (mounted && id == _requestId) setState(() => _people = p);
    } on ApiException {
      if (mounted && id == _requestId) setState(() => _people = const CalendarPeople());
    } finally {
      if (mounted && id == _requestId) setState(() => _loading = false);
    }
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _load(q.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final height = MediaQuery.of(context).size.height * 0.75;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(HrisSpace.s4, 0, HrisSpace.s4, HrisSpace.s2),
              child: TextField(
                key: const Key('leave_calendar_search'),
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Employee',
                  hintText: 'Everyone — or search a name',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: _onChanged,
              ),
            ),
            if (_people.truncated)
              Padding(
                padding: const EdgeInsets.fromLTRB(HrisSpace.s4, 0, HrisSpace.s4, HrisSpace.s2),
                child: Text('Showing the first matches — type a name to narrow the list.',
                    style: TextStyle(fontSize: HrisType.xs, color: t.muted)),
              ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: ListView(
                children: [
                  ListTile(
                    title: const Text('Everyone'),
                    selected: widget.selectedId.isEmpty,
                    onTap: () => Navigator.of(context).pop(const _PickResult(null)),
                  ),
                  if (!_loading && _people.items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(HrisSpace.s4),
                      child: Text('No matching employees', style: TextStyle(fontSize: HrisType.sm, color: t.muted)),
                    ),
                  for (final p in _people.items)
                    ListTile(
                      title: Text(p.label),
                      subtitle: p.hint.isEmpty ? null : Text(p.hint),
                      selected: widget.selectedId == '${p.id}',
                      onTap: () => Navigator.of(context).pop(_PickResult(p)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
