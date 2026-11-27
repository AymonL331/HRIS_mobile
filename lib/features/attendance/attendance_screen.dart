import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/time/duration_label.dart';
import '../../core/time/manila_time.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/message_banner.dart';
import '../../shared/widgets/status_badge.dart';
import 'attendance_controller.dart';
import 'attendance_models.dart';
import 'attendance_summary_view.dart';
import 'correction_form_screen.dart';

/// My Attendance, drawn as the website's page on a phone (user 2026-11-24): the
/// subtitle, Records | Summary + "File a correction", the Face enrollment card,
/// the "Daily time record" table (Date · Clock In · Clock Out · Worked · Late ·
/// Undertime · Status · Method) that scrolls sideways, and "My correction
/// requests" as a table. Older months still load with "Load previous month".
/// No coordinates anywhere — the model does not even carry them.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  bool _summary = false;
  bool _summaryOpened = false; // mounted from the first visit on, then kept

  Future<void> _fileCorrection() async {
    final c = context.read<AttendanceController>();
    final filed = await CorrectionFormScreen.open(context, api: c.api, today: c.today);
    if (filed != true || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Correction request submitted.')));
    await c.loadCorrections();
  }

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return Column(
      children: [
        // The web page's subtitle, which changes with the view.
        Padding(
          padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s2, HrisSpace.s4, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _summary
                  ? 'Your attendance at a glance — totals for the period, month by month.'
                  : 'Your daily time record and corrections.',
              style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.muted),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s2, HrisSpace.s4, HrisSpace.s2),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Records')),
                    ButtonSegment(value: true, label: Text('Summary')),
                  ],
                  selected: {_summary},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() {
                    _summary = s.first;
                    _summaryOpened = _summaryOpened || _summary;
                  }),
                ),
              ),
              const SizedBox(width: HrisSpace.s2),
              FilledButton(onPressed: _fileCorrection, child: const Text('File a correction')),
            ],
          ),
        ),
        // Both views stay alive once opened, so switching keeps each one's scroll position.
        Expanded(
          child: IndexedStack(
            index: _summary ? 1 : 0,
            children: [const _RecordsView(), if (_summaryOpened) const AttendanceSummaryView() else const SizedBox.shrink()],
          ),
        ),
      ],
    );
  }
}

/// The day-by-day record (the web's Records view).
class _RecordsView extends StatefulWidget {
  const _RecordsView();

  @override
  State<_RecordsView> createState() => _RecordsViewState();
}

class _RecordsViewState extends State<_RecordsView> {
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
          // A plain card with the error banner, as the web: one red element, not two.
          child: AppCard(
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

    return RefreshIndicator(
      onRefresh: c.refresh,
      child: ListView(
        // Pull works even when the page is short (an empty month, an error card).
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s1, HrisSpace.s4, HrisSpace.s5),
        children: [
          if (c.error != null) ...[MessageBanner.warning(c.error!), const SizedBox(height: HrisSpace.s3)],
          if (c.biometric != null) ...[_BiometricCard(status: c.biometric!), const SizedBox(height: HrisSpace.s4)],
          // THE WEB'S "Daily time record" (user 2026-11-24: "my attendance should look
          // like the my attendance in web app in mobile view") — the same eight
          // columns in a table that scrolls sideways, as the web's does on a phone.
          _SectionTitle('Daily time record'),
          const SizedBox(height: HrisSpace.s2),
          if (c.days.isEmpty)
            _EmptyBox(text: 'No attendance records yet. Your daily time record will appear here once you start clocking in.')
          else
            _DtrTable(days: c.days),
          const SizedBox(height: HrisSpace.s3),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${c.days.length} day${c.days.length == 1 ? '' : 's'} · ${_range(c.months)}',
                  style: TextStyle(fontSize: HrisType.xs, height: 18 / 12, color: t.muted),
                ),
              ),
              OutlinedButton.icon(
                onPressed: c.loading ? null : c.loadPrevious,
                icon: c.loading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.history, size: 18),
                label: const Text('Load previous month'),
              ),
            ],
          ),
          if (c.corrections.isNotEmpty) ...[
            const SizedBox(height: HrisSpace.s5),
            _SectionTitle('My correction requests'),
            const SizedBox(height: HrisSpace.s2),
            _CorrectionsTable(items: c.corrections),
          ],
        ],
      ),
    );
  }

  static String _range(List<DtrMonth> months) {
    if (months.isEmpty) return '';
    final first = ManilaTime.monthLabel(months.first.year, months.first.month);
    final last = ManilaTime.monthLabel(months.last.year, months.last.month);
    return months.length == 1 ? first : '$last – $first';
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return Text(text, style: TextStyle(fontSize: HrisType.md, fontWeight: HrisType.semibold, height: 24 / 16, color: t.text));
  }
}

class _EmptyBox extends StatelessWidget {
  final String text;
  const _EmptyBox({required this.text});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(HrisSpace.s5),
      decoration: BoxDecoration(color: t.surface, border: Border.all(color: t.border), borderRadius: BorderRadius.circular(HrisRadius.md)),
      child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text2)),
    );
  }
}

/// The web page's "Face enrollment" card.
class _BiometricCard extends StatelessWidget {
  final BiometricStatus status;
  const _BiometricCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final note = status.enrolled
        ? 'You can clock in and out by face. Model ${status.modelVersion ?? '—'}${status.consentGiven ? ' · consent on file' : ''}.'
        : 'You aren’t enrolled for face timekeeping. Ask HR to enroll you, or clock in manually — a correction can be filed if a time is missed.';
    return Container(
      padding: const EdgeInsets.all(HrisSpace.s4),
      decoration: BoxDecoration(color: t.surface, border: Border.all(color: t.border), borderRadius: BorderRadius.circular(HrisRadius.md)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Face enrollment',
                    style: TextStyle(fontSize: HrisType.sm, fontWeight: HrisType.semibold, height: 20 / 14, color: t.text)),
              ),
              StatusBadge(status.enrolled ? 'Enrolled' : 'Not enrolled', tone: status.enrolled ? StatusTone.success : StatusTone.neutral),
            ],
          ),
          const SizedBox(height: HrisSpace.s2),
          Text(note, style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text2)),
        ],
      ),
    );
  }
}

/// A bordered table that scrolls sideways — how the web's tables sit on a phone.
class _WebTable extends StatelessWidget {
  final List<String> headers;
  final List<List<Widget>> rows;
  const _WebTable({required this.headers, required this.rows});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    Widget cell(Widget child) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s3, vertical: HrisSpace.s3),
          child: child,
        );
    return Container(
      decoration: BoxDecoration(color: t.surface, border: Border.all(color: t.border), borderRadius: BorderRadius.circular(HrisRadius.md)),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          defaultVerticalAlignment: TableCellVerticalAlignment.top,
          border: TableBorder(horizontalInside: BorderSide(color: t.border)),
          children: [
            TableRow(
              decoration: BoxDecoration(color: t.bg),
              children: [
                for (final h in headers)
                  cell(Text(h.toUpperCase(),
                      style: TextStyle(fontFamily: HrisFont.mono, fontSize: HrisType.xs, letterSpacing: 0.6, height: 16 / 12, color: t.muted))),
              ],
            ),
            for (final r in rows) TableRow(children: [for (final c in r) cell(c)]),
          ],
        ),
      ),
    );
  }
}

const _statusLabels = {'present': 'Present', 'late': 'Late', 'absent': 'Absent', 'official_business': 'Official Business'};
const _statusTones = {
  'present': StatusTone.success,
  'late': StatusTone.warning,
  'absent': StatusTone.danger,
  'official_business': StatusTone.info,
};
const _dayTypeLabels = {'on_leave': 'On Leave', 'holiday': 'Holiday', 'rest_day': 'Rest day', 'no_record': 'No record'};
const _dayTypeTones = {
  'on_leave': StatusTone.success,
  'holiday': StatusTone.info,
  'rest_day': StatusTone.quiet,
  'no_record': StatusTone.quiet,
};
const _methodLabels = {
  'manual': 'Manual',
  'face': 'Face',
  'device': 'Device',
  'import': 'Import',
  'system': 'System',
  'mobile': 'Mobile app',
  'web': 'Web clock',
};

/// THE DAILY TIME RECORD — the web's columns: Date · Clock In · Clock Out ·
/// Worked · Late · Undertime · Status · Method. No coordinates: the model has none.
class _DtrTable extends StatelessWidget {
  final List<DtrDay> days;
  const _DtrTable({required this.days});

  String _part(String? p) => p == 'am_half' || p == 'am'
      ? ' (AM)'
      : p == 'pm_half' || p == 'pm'
          ? ' (PM)'
          : '';

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final body = TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text);
    final mono = TextStyle(fontFamily: HrisFont.mono, fontSize: HrisType.sm, height: 20 / 14, color: t.text);
    final dash = Text('—', style: body);

    Widget minutesCell(int minutes, String? reason) => minutes <= 0
        ? dash
        : ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(hoursMinutes(minutes), style: body),
                if (reason != null)
                  Text(reason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: HrisType.xs, height: 16 / 12, color: t.text2)),
              ],
            ),
          );

    String leaveText(DtrDay d) =>
        '${d.leaveTypeName != null ? ' · ${d.leaveTypeName}' : ''}${_part(d.leaveDayPart)}${d.leavePaymentType == 'unpaid' ? ' (Unpaid)' : ''}';

    Widget statusCell(DtrDay d) {
      if (d.status == null && d.dayType != 'worked') {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatusBadge('${_dayTypeLabels[d.dayType] ?? d.dayType}${d.dayType == 'on_leave' ? leaveText(d) : ''}',
                tone: _dayTypeTones[d.dayType] ?? StatusTone.neutral),
            if (d.dayType == 'holiday' && d.holidayTitle != null) ...[
              const SizedBox(height: 2),
              Text(d.holidayTitle!, style: TextStyle(fontSize: HrisType.xs, height: 16 / 12, color: t.text2)),
            ],
          ],
        );
      }
      return Wrap(
        spacing: HrisSpace.s1,
        runSpacing: HrisSpace.s1,
        children: [
          StatusBadge(_statusLabels[d.status] ?? d.status ?? '—', tone: _statusTones[d.status] ?? StatusTone.neutral),
          if (d.isUndertime) const StatusBadge('Undertime', tone: StatusTone.warning),
          if (d.isHalfDay) const StatusBadge('Half-day', tone: StatusTone.info),
          if (d.isOnLeave) StatusBadge('On Leave${leaveText(d)}', tone: StatusTone.success),
          if (d.isHolidayUnapproved) const StatusBadge('Holiday · not approved', tone: StatusTone.danger),
        ],
      );
    }

    Widget methodCell(DtrDay d) {
      // A corrected side is a button, as on the web: it opens the time it replaced.
      // A side the DTR import replaced reads "Import" (user 2026-11-24).
      Widget line(String dir, String? method, bool corrected) => Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 28, child: Text(dir, style: TextStyle(fontSize: HrisType.xs, color: t.muted))),
                corrected
                    ? InkWell(
                        key: Key('dtr_trail_${d.date}_${dir.toLowerCase()}'),
                        onTap: () => _showTrail(context, d),
                        child: d.correctedFromImport
                            ? StatusBadge(_methodLabels['import']!, tone: StatusTone.neutral)
                            : const StatusBadge('Corrected', tone: StatusTone.warning),
                      )
                    : StatusBadge(_methodLabels[method] ?? method ?? '—',
                        tone: method == 'mobile' || method == 'web' ? StatusTone.info : StatusTone.neutral),
              ],
            ),
          );
      if (d.inMethod == null && d.outMethod == null) return dash;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (d.inMethod != null) line('In', d.inMethod, d.clockInCorrected),
          if (d.outMethod != null) line('Out', d.outMethod, d.clockOutCorrected),
        ],
      );
    }

    return _WebTable(
      headers: const ['Date', 'Clock In', 'Clock Out', 'Worked', 'Late', 'Undertime', 'Status', 'Method'],
      rows: [
        for (final d in days)
          [
            Text(ManilaTime.dateOnly(d.date), style: body),
            Text(d.clockInAt == null ? '—' : ManilaTime.time(d.clockInAt!), style: mono),
            Text(d.clockOutAt == null ? '—' : ManilaTime.time(d.clockOutAt!), style: mono),
            Text(d.workedLabel.isEmpty ? '—' : d.workedLabel, style: body),
            minutesCell(d.lateMinutes, d.lateReason),
            minutesCell(d.undertimeMinutes, d.undertimeReason),
            statusCell(d),
            methodCell(d),
          ],
      ],
    );
  }
}

/// The trail of a corrected / imported day — the web's "Corrected time" /
/// "Imported time" dialog: what each side was before, and where it came from.
void _showTrail(BuildContext context, DtrDay d) {
  final t = HrisTokens.of(context);
  final body = TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text);
  final muted = TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.muted);
  String was(DateTime? at, String? method) => at == null
      ? 'No punch'
      : '${ManilaTime.time(at)}${method == null ? '' : ' (${_methodLabels[method] ?? method})'}';
  Widget side(String label, DateTime? orig, String? method, DateTime? now) => Padding(
        padding: const EdgeInsets.only(bottom: HrisSpace.s2),
        child: Row(
          children: [
            SizedBox(width: 72, child: Text(label, style: muted)),
            Flexible(child: Text(was(orig, method), style: body)),
            Padding(padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s2), child: Text('→', style: muted)),
            Text(now == null ? '—' : ManilaTime.time(now), style: body.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      );
  final source = d.correctionSource == 'request'
      ? 'Approved correction request'
      : d.correctedFromImport
          ? 'Imported DTR file (Excel)'
          : d.correctionSource == 'admin'
              ? 'Corrected by an admin'
              : '—';
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(d.correctedFromImport ? 'Imported time' : 'Corrected time'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ManilaTime.dateOnly(d.date), style: muted),
          const SizedBox(height: HrisSpace.s3),
          if (d.clockInCorrected) side('Clock in', d.clockInOriginalAt, d.clockInOriginalMethod, d.clockInAt),
          if (d.clockOutCorrected) side('Clock out', d.clockOutOriginalAt, d.clockOutOriginalMethod, d.clockOutAt),
          const SizedBox(height: HrisSpace.s2),
          Text('Source: $source', style: body),
          if (d.correctedByName != null)
            Text('${d.correctedFromImport ? 'Imported' : 'Corrected'} by: ${d.correctedByName}', style: body),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
    ),
  );
}

/// MY CORRECTION REQUESTS — the web's table: Date · Requested In · Requested Out ·
/// Status · Reason · Proof.
class _CorrectionsTable extends StatelessWidget {
  final List<CorrectionRequest> items;
  const _CorrectionsTable({required this.items});

  static const _labels = {'pending': 'Pending', 'approved': 'Approved', 'rejected': 'Rejected', 'cancelled': 'Cancelled'};
  static const _tones = {
    'pending': StatusTone.warning,
    'approved': StatusTone.success,
    'rejected': StatusTone.danger,
    'cancelled': StatusTone.neutral,
  };

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final body = TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text);
    final mono = TextStyle(fontFamily: HrisFont.mono, fontSize: HrisType.sm, height: 20 / 14, color: t.text);
    String when(DateTime? at) => at == null ? '—' : ManilaTime.dateTime(at);
    return _WebTable(
      headers: const ['Date', 'Requested In', 'Requested Out', 'Status', 'Reason', 'Proof'],
      rows: [
        for (final r in items)
          [
            Text(ManilaTime.dateOnly(r.date), style: body),
            Text(when(r.requestedClockIn), style: mono),
            Text(when(r.requestedClockOut), style: mono),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                StatusBadge(_labels[r.status] ?? r.status, tone: _tones[r.status] ?? StatusTone.neutral),
                // WHY it was rejected — the approver's remarks (2026-11-27).
                if (r.status == 'rejected')
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Text(
                        (r.rejectionRemarks ?? '').isEmpty ? 'No reason was given.' : 'Reason: ${r.rejectionRemarks}',
                        style: TextStyle(fontSize: HrisType.xs, color: t.danger.text),
                      ),
                    ),
                  ),
              ],
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text((r.reason ?? '').isEmpty ? '—' : r.reason!, style: body),
            ),
            Text((r.proofPhotoUrl ?? '').isEmpty ? '—' : 'Photo attached', style: TextStyle(fontSize: HrisType.sm, color: t.text2)),
          ],
      ],
    );
  }
}
