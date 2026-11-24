import 'package:flutter/material.dart';

import '../../core/http/api_exception.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/kit.dart';
import 'overtime_api.dart';
import 'overtime_files.dart';
import 'overtime_models.dart';

/// The Overtime Accomplishment Report (web MyOvertimeReportPrintPage +
/// OvertimeAccomplishmentDocument), read-only on the phone — the same document,
/// section for section; printing stays on the website. Every value is the server's.
class OvertimeReportScreen extends StatefulWidget {
  final OvertimeApi api;
  final int requestId;
  final String baseUrl;

  const OvertimeReportScreen({super.key, required this.api, required this.requestId, required this.baseUrl});

  static Future<void> open(BuildContext context, {required OvertimeApi api, required int requestId, required String baseUrl}) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => OvertimeReportScreen(api: api, requestId: requestId, baseUrl: baseUrl)),
      );

  @override
  State<OvertimeReportScreen> createState() => _OvertimeReportScreenState();
}

class _OvertimeReportScreenState extends State<OvertimeReportScreen> {
  OvertimeReport? _report;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.api.report(widget.requestId);
      if (mounted) setState(() => _report = r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('Accomplishment report')),
      body: SafeArea(
        child: _loading
            ? const LoadingBlock(semanticsLabel: 'Loading the accomplishment report')
            : _error != null
                ? Padding(
                    padding: const EdgeInsets.all(HrisSpace.s4),
                    child: StatePanel(
                      title: "Couldn't load the report",
                      message: _error,
                      error: true,
                      action: OutlinedButton(onPressed: _load, child: const Text('Try again')),
                    ),
                  )
                : r == null
                    ? const SizedBox.shrink()
                    : _Document(report: r, baseUrl: widget.baseUrl),
      ),
    );
  }
}

class _Document extends StatelessWidget {
  final OvertimeReport report;
  final String baseUrl;

  const _Document({required this.report, required this.baseUrl});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final r = report;
    final e = r.employee;
    final approver = r.steps.where((s) => s.action == 'approved').firstOrNull?.approverName ?? '';

    Widget sectionTitle(String s) => Padding(
          padding: const EdgeInsets.only(top: HrisSpace.s5, bottom: HrisSpace.s2),
          child: Text(s.toUpperCase(),
              style: TextStyle(
                  fontFamily: HrisFont.mono, fontSize: 11, letterSpacing: 1.1, fontWeight: HrisType.medium, color: t.muted)),
        );

    Widget field(String label, Object? value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: HrisSpace.s1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 120, child: Text(label, style: TextStyle(fontSize: HrisType.xs, height: 20 / 12, color: t.text2))),
              Expanded(
                child: Text(
                  value == null || '$value'.isEmpty ? '—' : '$value',
                  style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text),
                ),
              ),
            ],
          ),
        );

    final dateCount = r.dateCount ?? r.dates.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s4, HrisSpace.s4, HrisSpace.s6),
      children: [
        Container(
          padding: const EdgeInsets.all(HrisSpace.s4),
          decoration: BoxDecoration(
            color: t.surface,
            border: Border.all(color: t.border),
            borderRadius: BorderRadius.circular(HrisRadius.panel),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- letterhead ---
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.companyName ?? '—', style: TextStyle(fontSize: HrisType.xs, color: t.text2)),
                        const SizedBox(height: 2),
                        Text('Overtime Accomplishment Report',
                            style: TextStyle(fontSize: HrisType.md, fontWeight: HrisType.semibold, color: t.text)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(r.refNo, style: TextStyle(fontFamily: HrisFont.mono, fontSize: HrisType.xs, color: t.text)),
                      Text(otStatusLabels[r.status] ?? r.status, style: TextStyle(fontSize: HrisType.xs, color: t.text2)),
                    ],
                  ),
                ],
              ),
              Divider(height: HrisSpace.s5, color: t.border),

              sectionTitle('Employee'),
              field('Name', e['name']),
              field('Employee code', e['employee_code']),
              field('Position', e['designation']),
              field('Department', e['department']),
              field('Branch', e['branch']),
              field('Filed', formatDateTime(r.dateFiled)),

              sectionTitle('Approved overtime'),
              field('Hours per date', hoursLabel(r.otHours)),
              field('Window', '${formatTimeOfDay(r.startTime)} – ${formatTimeOfDay(r.endTime)}'),
              field('Type', otTypeLabels[r.otType] ?? r.otType),
              field('Dates covered', '$dateCount'),
              field('Purpose', r.purpose),

              sectionTitle('Approval'),
              if (r.steps.isEmpty)
                Text('Approved directly, without a configured approval chain.',
                    style: TextStyle(fontSize: HrisType.sm, color: t.muted))
              else
                for (final s in r.steps)
                  Container(
                    margin: const EdgeInsets.only(bottom: HrisSpace.s2),
                    padding: const EdgeInsets.all(HrisSpace.s3),
                    decoration: BoxDecoration(
                      border: Border.all(color: t.border),
                      borderRadius: BorderRadius.circular(HrisRadius.control),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        field('Level', s.level),
                        field('Decision', s.action),
                        field('Approver', s.approverName == null
                            ? null
                            : '${s.approverName}${s.approverRole != null ? ' (${s.approverRole})' : ''}'),
                        field('Date', s.actedAt != null ? formatDateTime(s.actedAt) : '—'),
                        field('Remarks', s.remarks),
                      ],
                    ),
                  ),

              sectionTitle('Accomplishment'),
              for (final d in r.dates)
                Padding(
                  padding: const EdgeInsets.only(bottom: HrisSpace.s3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: HrisSpace.s2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(formatDateOnly(d.date),
                              style: TextStyle(fontSize: HrisType.sm, fontWeight: HrisType.semibold, color: t.text)),
                          d.accomplishmentAt != null
                              ? Text('Submitted ${formatDateTime(d.accomplishmentAt)}',
                                  style: TextStyle(fontSize: HrisType.xs, color: t.success.text))
                              : Text('Not yet reported', style: TextStyle(fontSize: HrisType.xs, color: t.danger.text)),
                        ],
                      ),
                      const SizedBox(height: HrisSpace.s1),
                      d.accomplishmentNote != null
                          ? Text(d.accomplishmentNote!, style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text))
                          : Text('No remarks were written for this date.',
                              style: TextStyle(fontSize: HrisType.sm, color: t.muted)),
                      if (d.photos.isNotEmpty) ...[
                        const SizedBox(height: HrisSpace.s2),
                        OvertimeThumbs(
                          urls: d.photos.map((p) => p.fileUrl).toList(),
                          baseUrl: baseUrl,
                          alt: 'Accomplishment for ${formatDateOnly(d.date)}',
                          size: 72,
                        ),
                      ],
                    ],
                  ),
                ),
              Text(
                '${r.reportedCount} of $dateCount dates reported · ${r.photoCount} picture${r.photoCount == 1 ? '' : 's'} attached',
                style: TextStyle(fontSize: HrisType.xs, color: t.text2),
              ),

              const SizedBox(height: HrisSpace.s6),
              Row(
                children: [
                  Expanded(child: _Sign(name: '${e['name'] ?? ''}', role: 'Submitted by')),
                  const SizedBox(width: HrisSpace.s4),
                  Expanded(child: _Sign(name: approver, role: 'Approved by')),
                ],
              ),
              Divider(height: HrisSpace.s6, color: t.border),
              Text(
                '${r.companyName ?? ''}${r.companyCode != null ? ' · ${r.companyCode}' : ''} · ${r.refNo}',
                style: TextStyle(fontSize: HrisType.xs, color: t.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: HrisSpace.s3),
        Text('To print this report, open it on the ATLAS website.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: HrisType.xs, color: t.muted)),
      ],
    );
  }
}

class _Sign extends StatelessWidget {
  final String name;
  final String role;
  const _Sign({required this.name, required this.role});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: HrisSpace.s6),
        Container(height: 1, color: t.borderStrong),
        const SizedBox(height: HrisSpace.s1),
        Text(name, textAlign: TextAlign.center, style: TextStyle(fontSize: HrisType.sm, color: t.text)),
        Text(role, textAlign: TextAlign.center, style: TextStyle(fontSize: HrisType.xs, color: t.muted)),
      ],
    );
  }
}
