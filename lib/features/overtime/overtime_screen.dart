import 'package:flutter/material.dart';

import '../../core/http/api_exception.dart';
import '../../shared/button_styles.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/kit.dart';
import '../../shared/widgets/status_badge.dart';
import 'overtime_accomplishment.dart';
import 'overtime_api.dart';
import 'overtime_files.dart';
import 'overtime_models.dart';
import 'overtime_report_screen.dart';
import 'overtime_request_screen.dart';
import 'overtime_requirements_screen.dart';

/// OVERTIME & HOLIDAY WORK — the web's My Overtime page on the phone (Self-Service).
///
/// The flow, in the order it happens: file → approver decides → (if approved)
/// report the accomplishment per date. Two money rules shown where they can still
/// change behaviour: overtime is paid only if the clock-out reaches the approved
/// end, and an approved date still owes an accomplishment until one is sent.
/// Holiday work is paid as the holiday premium — no gate, no accomplishment.
class OvertimeScreen extends StatefulWidget {
  final OvertimeApi api;

  /// The environment's base URL, for the stored forms and pictures.
  final String baseUrl;

  /// Whether this page is the one showing (the shell keeps every page built):
  /// it loads when first opened, and again each time it is opened.
  final bool active;

  final OvertimePickers pickers;

  /// Cross-page links (none on this page today; kept for the shell's contract).
  final ValueChanged<String>? onNavigate;

  /// Today (Manila YYYY-MM-DD) — a date after it "Not yet worked". For tests.
  final String? today;

  const OvertimeScreen({
    super.key,
    required this.api,
    required this.baseUrl,
    this.active = true,
    this.pickers = const OvertimePickers(),
    this.onNavigate,
    this.today,
  });

  @override
  State<OvertimeScreen> createState() => _OvertimeScreenState();
}

class _OvertimeScreenState extends State<OvertimeScreen> {
  List<OvertimeRequest> _requests = const [];
  OvertimePagination _pagination = const OvertimePagination();
  int _page = 1;
  bool _loading = false;
  bool _loadedOnce = false;
  String? _error;
  OvertimeIdentity? _identity;
  int _seq = 0;

  // WHICH date row has a panel open, by id, and which kind ('report' | 'view').
  int? _openDateId;
  String? _openKind;

  @override
  void initState() {
    super.initState();
    if (widget.active) _activate();
  }

  @override
  void didUpdateWidget(OvertimeScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _activate();
  }

  void _activate() {
    _load();
    _loadIdentity();
  }

  Future<void> _loadIdentity() async {
    try {
      final id = await widget.api.identity();
      if (mounted) setState(() => _identity = id);
    } on ApiException {
      // The form then shows dashes, as the web does when the profile fails.
    }
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.api.list(page: _page);
      if (!mounted || seq != _seq) return;
      setState(() {
        _requests = res.items;
        _pagination = res.pagination;
      });
    } on ApiException catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _error = e.message;
        _requests = const [];
      });
    } finally {
      if (mounted && seq == _seq) {
        setState(() {
          _loading = false;
          _loadedOnce = true;
        });
      }
    }
  }

  void _goToPage(int p) {
    setState(() => _page = p);
    _load();
  }

  void _toast(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> _file() async {
    final message = await OvertimeRequestScreen.open(context, api: widget.api, identity: _identity, pickers: widget.pickers);
    if (message != null && mounted) {
      _toast(message);
      await _load();
    }
  }

  Future<void> _requirements(OvertimeRequest r) async {
    final saved = await OvertimeRequirementsScreen.open(context, api: widget.api, request: r, pickers: widget.pickers);
    if (saved == true && mounted) await _load();
  }

  void _openPanel(OvertimeDate d, String kind) => setState(() {
        _openDateId = d.id;
        _openKind = kind;
      });

  void _closePanel() => setState(() {
        _openDateId = null;
        _openKind = null;
      });

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final initialLoad = (_loading || !_loadedOnce) && _requests.isEmpty && _error == null;
    final today = widget.today ?? manilaToday();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s2, HrisSpace.s4, HrisSpace.s6),
        children: [
          Text(
            'File overtime — or work on a holiday — before the day. Report what you accomplished once overtime is approved.',
            style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text2),
          ),
          const SizedBox(height: HrisSpace.s3),
          FilledButton(onPressed: _file, child: const Text('File overtime or holiday work')),
          const SizedBox(height: HrisSpace.s4),
          if (initialLoad)
            // A hidden page must not spin (the shell keeps it built).
            widget.active ? const LoadingBlock(semanticsLabel: 'Loading my overtime') : const SizedBox.shrink()
          else if (!_loading && _error != null)
            StatePanel(
              title: "Couldn't load your overtime",
              message: _error,
              error: true,
              action: OutlinedButton(onPressed: _load, child: const Text('Try again')),
            )
          else if (!_loading && _requests.isEmpty)
            const StatePanel(
              title: 'No overtime or holiday work filed yet',
              message: 'Need to work past your schedule, or on a holiday? File it first — it is only paid once it has been approved.',
            )
          else ...[
            for (final r in _requests) ...[
              _card(context, r, today),
              const SizedBox(height: HrisSpace.s4),
            ],
          ],
          if (_pagination.totalPages > 1)
            Padding(
              padding: const EdgeInsets.only(top: HrisSpace.s1),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Page ${_pagination.page} of ${_pagination.totalPages} · ${_pagination.total} total',
                      style: TextStyle(fontSize: HrisType.sm, color: t.muted),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: _page <= 1 || _loading ? null : () => _goToPage(_page - 1),
                    child: const Text('Previous'),
                  ),
                  const SizedBox(width: HrisSpace.s2),
                  OutlinedButton(
                    onPressed: _page >= _pagination.totalPages || _loading ? null : () => _goToPage(_page + 1),
                    child: const Text('Next'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, OvertimeRequest r, String today) {
    final t = HrisTokens.of(context);
    final holiday = r.holiday;
    final canReport = otCanReport(r.status) && !holiday;
    final small = TextStyle(fontSize: HrisType.xs, height: 18 / 12, color: t.muted);

    return Container(
      key: ValueKey('ot_card_${r.id}'),
      padding: const EdgeInsets.all(HrisSpace.s4),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(HrisRadius.panel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: HrisSpace.s3,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(hoursLabel(r.otHours),
                        style: TextStyle(fontSize: HrisType.md, fontWeight: HrisType.semibold, color: t.text)),
                    Text('${formatTimeOfDay(r.startTime)} – ${formatTimeOfDay(r.endTime)}',
                        style: TextStyle(fontSize: HrisType.sm, color: t.text)),
                    Text(otTypeLabels[r.otType] ?? r.otType, style: TextStyle(fontSize: HrisType.sm, color: t.muted)),
                  ],
                ),
              ),
              const SizedBox(width: HrisSpace.s2),
              StatusBadge(otStatusLabels[r.status] ?? r.status, tone: otStatusTone(r.status)),
            ],
          ),

          // Set by my admin (migration 122) — already approved; the paperwork is mine.
          if (r.assignedBy != null && r.status == 'approved') _setByAdmin(context, r),

          if (r.purpose != null) ...[
            const SizedBox(height: HrisSpace.s3),
            Text(r.purpose!, style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text)),
          ],

          if (holiday) ...[
            const SizedBox(height: HrisSpace.s3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                OvertimeThumbs(
                  urls: r.files,
                  baseUrl: widget.baseUrl,
                  alt: 'Approved holiday work form',
                  emptyLabel: 'No form',
                ),
                const SizedBox(width: HrisSpace.s3),
                Expanded(
                  child: Text(
                    'Paid as holiday pay if you worked your last scheduled day before the holiday.',
                    style: TextStyle(fontSize: HrisType.xs, height: 18 / 12, color: t.text2),
                  ),
                ),
              ],
            ),
          ],

          // The money rule, said where it can still change behaviour.
          if (canReport) ...[
            const SizedBox(height: HrisSpace.s3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s3, vertical: HrisSpace.s2),
              decoration: BoxDecoration(
                color: t.info.bg,
                border: Border.all(color: t.info.border),
                borderRadius: BorderRadius.circular(HrisRadius.control),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: t.info.solid, borderRadius: BorderRadius.circular(1)),
                    ),
                  ),
                  const SizedBox(width: HrisSpace.s2),
                  Expanded(
                    child: Text(
                      'Paid only for the dates you clock out at ${formatTimeOfDay(r.endTime)} or later. '
                      'Leaving earlier forfeits that date.',
                      style: TextStyle(fontSize: HrisType.xs, height: 18 / 12, color: t.text),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: HrisSpace.s3),
          for (final d in r.dates) ...[
            _dateRow(context, r, d, today, holiday: holiday, canReport: canReport),
            const SizedBox(height: HrisSpace.s2),
          ],

          if (canReport && r.accomplishmentsOutstanding > 0) ...[
            const SizedBox(height: HrisSpace.s1),
            Text('${r.accomplishmentsOutstanding} of ${r.dateCount} still to report.', style: small),
          ],
          // Only an approved filing has a report (the server enforces the same).
          if (canReport)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: t.primaryText),
                onPressed: () => OvertimeReportScreen.open(context, api: widget.api, requestId: r.id, baseUrl: widget.baseUrl),
                child: const Text('View accomplishment report', style: TextStyle(fontSize: HrisType.xs)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _setByAdmin(BuildContext context, OvertimeRequest r) {
    final t = HrisTokens.of(context);
    final holiday = r.holiday;
    // THREE STATES (user 2026-11-24, same as the website): amber = something to
    // add; GREEN = nothing left (holiday work with form + remarks, or overtime with
    // every date reported); blue = overtime still waiting on its reports to be paid.
    final missing = r.purpose == null || (holiday && r.files.isEmpty);
    final complete = !missing && (holiday || (r.dates.isNotEmpty && r.dates.every((d) => d.submitted)));
    final set = missing ? t.warning : (complete ? t.success : t.info);
    final by = r.assignedByName ?? 'your admin';
    final text = missing
        ? 'Set by $by — already approved. ${holiday ? 'Add the approved form and your remarks.' : 'Add your remarks.'}'
        : complete
            ? 'Set by $by — approved and complete. Nothing more to submit.'
            : 'Set by $by — approved. Report what you accomplished after each date to be paid.';
    final label = missing ? (holiday ? 'Add form and remarks' : 'Add remarks') : 'Change';
    return Container(
      margin: const EdgeInsets.only(top: HrisSpace.s3),
      padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s3, vertical: HrisSpace.s2),
      decoration: BoxDecoration(
        color: set.bg,
        border: Border.all(color: set.border),
        borderRadius: BorderRadius.circular(HrisRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: TextStyle(fontSize: HrisType.sm, fontWeight: HrisType.semibold, height: 20 / 14, color: t.text)),
          const SizedBox(height: HrisSpace.s2),
          missing
              ? FilledButton(onPressed: () => _requirements(r), child: Text(label))
              : FilledButton(
                  style: HrisButtonStyles.secondary(context), onPressed: () => _requirements(r), child: Text(label)),
        ],
      ),
    );
  }

  Widget _dateRow(BuildContext context, OvertimeRequest r, OvertimeDate d, String today,
      {required bool holiday, required bool canReport}) {
    final t = HrisTokens.of(context);
    final isOpen = _openDateId == d.id;
    final dateLabel = Text(formatDateOnly(d.date),
        style: TextStyle(fontSize: HrisType.sm, fontWeight: HrisType.semibold, color: t.text));
    final note = TextStyle(fontSize: HrisType.xs, color: t.muted);
    final box = BoxDecoration(
      border: Border.all(color: t.border),
      borderRadius: BorderRadius.circular(HrisRadius.control),
    );

    // Submitted is FINAL: the row becomes a way to read back what was handed in.
    if (d.submitted) {
      return Container(
        key: ValueKey('ot_date_${d.id}'),
        decoration: box,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(HrisRadius.control),
              onTap: () => isOpen ? _closePanel() : _openPanel(d, 'view'),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s3, vertical: HrisSpace.s3),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: HrisSpace.s2,
                  runSpacing: 2,
                  children: [
                    dateLabel,
                    Wrap(
                      spacing: HrisSpace.s2,
                      children: [
                        Text('Accomplishment submitted', style: TextStyle(fontSize: HrisType.xs, color: t.success.text)),
                        if (d.photos.isNotEmpty)
                          Text('${d.photos.length} picture${d.photos.length == 1 ? '' : 's'}', style: note),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (isOpen && _openKind == 'view')
              Padding(
                padding: const EdgeInsets.fromLTRB(HrisSpace.s3, 0, HrisSpace.s3, HrisSpace.s3),
                child: OvertimeAccomplishmentView(dateRow: d, baseUrl: widget.baseUrl, onClose: _closePanel),
              ),
          ],
        ),
      );
    }

    // A date after today has not been worked yet — nothing to report about it.
    final notYet = d.date.compareTo(today) > 0;
    final Widget trailing;
    if (holiday) {
      trailing = Text(r.status == 'pending' ? 'Awaiting approval' : r.status == 'approved' ? 'Approved to work' : '—', style: note);
    } else if (canReport) {
      trailing = Wrap(
        spacing: HrisSpace.s2,
        runSpacing: HrisSpace.s1,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (notYet) Text('Not yet worked', style: note),
          if (notYet)
            Tooltip(
              message: 'You can report this once the overtime date arrives.',
              child: FilledButton(
                style: HrisButtonStyles.secondary(context, minHeight: 36),
                onPressed: null,
                child: const Text('Report accomplishment'),
              ),
            )
          else
            FilledButton(
              style: HrisButtonStyles.secondary(context, minHeight: 36),
              onPressed: () => isOpen ? _closePanel() : _openPanel(d, 'report'),
              child: Text(isOpen ? 'Cancel' : 'Report accomplishment'),
            ),
        ],
      );
    } else {
      trailing = Text(r.status == 'pending' ? 'Awaiting approval' : '—', style: note);
    }

    return Container(
      key: ValueKey('ot_date_${d.id}'),
      padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s3, vertical: HrisSpace.s2),
      decoration: box,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: HrisSpace.s2,
            runSpacing: HrisSpace.s1,
            children: [dateLabel, trailing],
          ),
          // Opens HERE, under the row that was tapped.
          if (isOpen && _openKind == 'report')
            OvertimeAccomplishmentForm(
              key: ValueKey('ot_form_${d.id}'),
              api: widget.api,
              dateRow: d,
              picker: widget.pickers.photo,
              onCancel: _closePanel,
              onSubmitted: () {
                _closePanel();
                _load();
              },
            ),
        ],
      ),
    );
  }
}
