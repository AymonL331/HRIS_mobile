import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/format/money.dart';
import '../../core/http/api_exception.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/message_banner.dart';
import '../attendance/correction_form_screen.dart' show PickedProof;
import 'overtime_api.dart';
import 'overtime_files.dart';
import 'overtime_models.dart';

/// FILE OVERTIME OR HOLIDAY WORK — the web's OvertimeRequestDialog on the phone.
///
/// Asks for HOURS, never a start time: the window comes from the employee's own
/// schedule (server). When the chosen date is a holiday the SERVER says so and
/// the form switches to holiday work: exactly the full workday, locked, with the
/// management-approved form required. The preview is fetched, never computed.
///
/// Pops with the success message once filed.
class OvertimeRequestScreen extends StatefulWidget {
  final OvertimeApi api;
  final OvertimeIdentity? identity;
  final OvertimePickers pickers;

  /// Today (Manila YYYY-MM-DD) — the "Date filed" line. Injectable for tests.
  final String? today;

  /// The preview's debounce (the web's 300 ms).
  final Duration debounce;

  const OvertimeRequestScreen({
    super.key,
    required this.api,
    this.identity,
    this.pickers = const OvertimePickers(),
    this.today,
    this.debounce = const Duration(milliseconds: 300),
  });

  static Future<String?> open(
    BuildContext context, {
    required OvertimeApi api,
    OvertimeIdentity? identity,
    OvertimePickers pickers = const OvertimePickers(),
  }) =>
      Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => OvertimeRequestScreen(api: api, identity: identity, pickers: pickers)),
      );

  @override
  State<OvertimeRequestScreen> createState() => _OvertimeRequestScreenState();
}

class _OvertimeRequestScreenState extends State<OvertimeRequestScreen> {
  final _hours = TextEditingController();
  final _purpose = TextEditingController();
  final List<String> _dates = [];
  String? _datePick;
  Map<String, String?> _errors = {};
  String? _formError;
  bool _submitting = false;
  OvertimeWindow? _preview;
  String _previewError = '';
  List<PickedProof> _forms = [];
  Timer? _timer;
  int _previewSeq = 0;
  String _lastPreviewKey = '';

  @override
  void initState() {
    super.initState();
    _hours.addListener(_schedulePreview);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _hours.dispose();
    _purpose.dispose();
    super.dispose();
  }

  /// WHAT WILL ACTUALLY BE FILED: the date in the picker counts too.
  List<String> get _effectiveDates => ({..._dates, ?_datePick}.toList()..sort());

  bool get _isHoliday => _preview?.isHoliday ?? false;
  num get _maxHours {
    final n = numOf(_preview?.maxHours);
    return n > 0 ? n : 8;
  }

  void _schedulePreview() {
    final key = '${_hours.text}|${_effectiveDates.join(',')}';
    if (key == _lastPreviewKey) return;
    _lastPreviewKey = key;
    _timer?.cancel();
    _timer = Timer(widget.debounce, _loadPreview);
  }

  Future<void> _loadPreview() async {
    final seq = ++_previewSeq;
    final n = num.tryParse(_hours.text.trim()) ?? 0;
    final list = _effectiveDates;
    if (!(n > 0) && list.isEmpty) {
      setState(() {
        _preview = null;
        _previewError = '';
      });
      return;
    }
    try {
      final res = await widget.api.window(hours: n > 0 ? n : null, dates: list);
      if (!mounted || seq != _previewSeq) return;
      setState(() {
        _preview = res;
        _previewError = '';
      });
      // HOLIDAY WORK is exactly the full workday: the hours ARE that day.
      if (res.isHoliday) {
        final full = numText(_maxHours);
        if (_hours.text != full) _hours.text = full;
        if (_errors['hours'] != null || _errors['ot_hours'] != null) {
          setState(() => _errors = {..._errors, 'hours': null, 'ot_hours': null});
        }
      }
    } on ApiException catch (e) {
      if (!mounted || seq != _previewSeq) return;
      setState(() {
        _preview = null;
        _previewError = n > 0 ? (e.message.isNotEmpty ? e.message : 'Could not work out the overtime window.') : '';
      });
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.tryParse(widget.today ?? manilaToday()) ?? DateTime.now();
    final current = DateTime.tryParse(_datePick ?? '') ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(now.year - 1, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'Date the overtime will be worked',
    );
    if (picked == null) return;
    String p(int n) => n.toString().padLeft(2, '0');
    setState(() {
      _datePick = '${picked.year}-${p(picked.month)}-${p(picked.day)}';
      _errors = {..._errors, 'dates': null};
    });
    _schedulePreview();
  }

  void _addDate() {
    final d = _datePick;
    if (d == null) return;
    setState(() {
      if (!_dates.contains(d)) _dates.add(d);
      _dates.sort();
      _datePick = null;
      _errors = {..._errors, 'dates': null};
    });
    _schedulePreview();
  }

  void _removeDate(String d) {
    setState(() => _dates.remove(d));
    _schedulePreview();
  }

  Map<String, String> _validate() {
    final next = <String, String>{};
    final n = _isHoliday ? _maxHours : (num.tryParse(_hours.text.trim()) ?? 0);
    if (!(n > 0)) {
      next['hours'] = _isHoliday ? 'Enter how many hours you will work on the holiday.' : 'Enter how many overtime hours you are requesting.';
    } else if (_isHoliday && n != _maxHours) {
      next['hours'] = 'Holiday work is exactly ${numText(_maxHours)} hours — one full workday.';
    } else if (!_isHoliday && n > maxOvertimeHours) {
      next['hours'] = 'Overtime is at most $maxOvertimeHours hours per date.';
    }
    if (_effectiveDates.isEmpty) next['dates'] = 'Choose the date the overtime will be worked.';
    if (_purpose.text.trim().isEmpty) {
      next['purpose'] = _isHoliday ? 'State why you need to work the holiday.' : 'State why the overtime is needed.';
    }
    if (_isHoliday && _forms.isEmpty) next['attachment_url'] = 'Attach the approved holiday work form.';
    return next;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final found = _validate();
    setState(() => _errors = found);
    if (found.isNotEmpty) return;

    final holiday = _isHoliday;
    final dates = _effectiveDates;
    setState(() {
      _submitting = true;
      _formError = null;
    });
    try {
      // Stage the approved forms first; the first URL goes on the filing.
      final urls = <String>[];
      for (final f in _forms) {
        final url = await widget.api.stageForm(f);
        if (url.isEmpty) throw const ApiException(status: 0, message: 'A file could not be uploaded. Please try again.');
        urls.add(url);
      }
      await widget.api.submit({
        'dates': dates,
        'ot_hours': holiday ? _maxHours : num.parse(_hours.text.trim()),
        'purpose': _purpose.text.trim(),
        if (urls.isNotEmpty) 'attachment_url': urls.first,
        if (urls.length > 1) 'more_attachment_urls': urls.sublist(1),
      });
      if (!mounted) return;
      Navigator.of(context).pop(
        holiday
            ? 'Holiday work filed. It now needs your approver.'
            : dates.length == 1
                ? 'Overtime filed. It now needs your approver.'
                : 'Overtime filed for ${dates.length} dates. One approval covers them all.',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if ((e.status == 422 || e.status == 409) && e.fieldErrors.isNotEmpty) {
          _errors = {...e.fieldErrors};
        } else {
          _formError = e.message.isNotEmpty ? e.message : 'Could not file the overtime request.';
        }
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final id = widget.identity;
    final holiday = _isHoliday;
    final preview = _preview;
    final today = widget.today ?? manilaToday();
    // Over the cap is said AS THE HOURS ARE TYPED and File stays off (user
    // 2026-11-24): no need to press File just to learn 4 hours is too many.
    final overCap = !holiday && (num.tryParse(_hours.text.trim()) ?? 0) > maxOvertimeHours;

    Widget identityRow(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 104,
                child: Text(label.toUpperCase(),
                    style: TextStyle(
                        fontFamily: HrisFont.mono, fontSize: 11, letterSpacing: 1.1, fontWeight: HrisType.medium, color: t.muted)),
              ),
              Expanded(child: Text(value, style: TextStyle(fontSize: HrisType.sm, color: t.text))),
            ],
          ),
        );

    final holidayNames = (preview?.holidays ?? const <HolidayTitle>[])
        .map((h) => '${formatDateOnly(h.date)} is ${h.title}')
        .join(' · ');

    return Scaffold(
      appBar: AppBar(title: const Text('File overtime or holiday work')),
      body: SafeArea(
        child: AbsorbPointer(
          absorbing: _submitting,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s4, HrisSpace.s4, HrisSpace.s6),
            children: [
              Text(
                'Enter how many hours you need. The start and end times come from your own schedule. '
                'Working a holiday? Pick the holiday date — the form switches to holiday work.',
                style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text2),
              ),
              const SizedBox(height: HrisSpace.s4),
              if (_formError != null) ...[
                MessageBanner.error(_formError!),
                const SizedBox(height: HrisSpace.s3),
              ],
              // Read from the profile, never typed — this is who the filing is for.
              Container(
                padding: const EdgeInsets.all(HrisSpace.s3),
                decoration: BoxDecoration(
                  color: t.surfaceSunken,
                  border: Border.all(color: t.border),
                  borderRadius: BorderRadius.circular(HrisRadius.control),
                ),
                child: Column(
                  children: [
                    identityRow('Employee', (id?.fullName ?? '').isEmpty ? '—' : id!.fullName),
                    identityRow('Department', id?.department ?? '—'),
                    identityRow('Designation', id?.designation ?? '—'),
                    identityRow('Date filed', formatDateOnly(today)),
                  ],
                ),
              ),
              const SizedBox(height: HrisSpace.s4),

              InkWell(
                key: const Key('ot_date_pick'),
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(HrisRadius.control),
                child: InputDecorator(
                  isEmpty: _datePick == null,
                  decoration: InputDecoration(
                    label: Text.rich(TextSpan(text: 'Date the overtime will be worked', children: [
                      TextSpan(text: ' *', style: TextStyle(color: t.danger.solid)),
                    ])),
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    errorText: _errors['dates'],
                    errorMaxLines: 3,
                    helperText: _dates.isNotEmpty
                        ? 'This date is included too. All of them are filed together and approved once.'
                        : 'Today is fine. Working the same hours on more than one day? Use “Add another date”.',
                    helperMaxLines: 3,
                    suffixIcon: const Icon(Icons.calendar_today_outlined),
                  ),
                  child: Text(
                    _datePick == null ? 'Select a date' : formatDateOnly(_datePick),
                    style: TextStyle(fontSize: HrisType.md, color: _datePick == null ? t.muted : t.text),
                  ),
                ),
              ),
              const SizedBox(height: HrisSpace.s2),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: _datePick == null ? null : _addDate,
                  child: const Text('Add another date'),
                ),
              ),
              if (_dates.isNotEmpty) ...[
                const SizedBox(height: HrisSpace.s2),
                Wrap(
                  spacing: HrisSpace.s2,
                  runSpacing: HrisSpace.s2,
                  children: [
                    for (final d in _dates)
                      InputChip(
                        label: Text(formatDateOnly(d)),
                        deleteButtonTooltipMessage: 'Remove ${formatDateOnly(d)}',
                        onDeleted: () => _removeDate(d),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: HrisSpace.s4),

              // HOLIDAY WORK — told by the server from the holiday calendar.
              if (holiday && preview != null) ...[
                Container(
                  key: const Key('ot_holiday_notice'),
                  padding: const EdgeInsets.all(HrisSpace.s3),
                  decoration: BoxDecoration(
                    color: t.warning.bg,
                    border: Border.all(color: t.warning.border),
                    borderRadius: BorderRadius.circular(HrisRadius.control),
                  ),
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: holidayNames.isEmpty ? 'This date is a holiday' : holidayNames,
                          style: const TextStyle(fontWeight: HrisType.semibold)),
                      if (preview.kindLabel != null) TextSpan(text: ' (${preview.kindLabel!.toLowerCase()})'),
                      TextSpan(
                        text: '\nYou are filing to WORK this holiday. Holiday work is one full workday — exactly '
                            '${numText(_maxHours)} hours, no more and no less — and needs the holiday work form approved by '
                            'management. File it before the holiday.',
                      ),
                    ]),
                    style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text),
                  ),
                ),
                const SizedBox(height: HrisSpace.s4),
              ],

              TextField(
                key: const Key('ot_hours'),
                controller: _hours,
                readOnly: holiday,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  label: Text.rich(TextSpan(
                    text: holiday ? 'Hours you will work (a full workday)' : 'Number of overtime hours requested',
                    children: [TextSpan(text: ' *', style: TextStyle(color: t.danger.solid))],
                  )),
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  errorText: _errors['hours'] ??
                      _errors['ot_hours'] ??
                      (overCap ? "Overtime can't be more than $maxOvertimeHours hours per date. Enter $maxOvertimeHours or less." : null),
                  errorMaxLines: 3,
                  helperText: holiday
                      ? 'Holiday work is always ${numText(_maxHours)} hours, from the start of your regular workday.'
                      : 'Up to $maxOvertimeHours hours per date. The start and end times are worked out from your own schedule.',
                  helperMaxLines: 3,
                ),
                // Every keystroke rebuilds, so the over-3-hours line shows and File turns off at once.
                onChanged: (_) => setState(() {
                  if (_errors['hours'] != null) _errors = {..._errors, 'hours': null};
                }),
              ),

              // The derived window + what it would pay. Both come from the server.
              if (preview != null && preview.startTime != null) ...[
                const SizedBox(height: HrisSpace.s3),
                Container(
                  key: const Key('ot_preview'),
                  padding: const EdgeInsets.all(HrisSpace.s3),
                  decoration: BoxDecoration(
                    color: t.surfaceSunken,
                    border: Border.all(color: t.border),
                    borderRadius: BorderRadius.circular(HrisRadius.control),
                  ),
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: '${formatTimeOfDay(preview.startTime)} – ${formatTimeOfDay(preview.endTime)}',
                        style: const TextStyle(fontWeight: HrisType.semibold),
                      ),
                      if (holiday) ...[
                        TextSpan(text: ' · ${hoursLabel(preview.hours)} · about '),
                        TextSpan(
                            text: Money.format(preview.estimatedPremium), style: const TextStyle(fontWeight: HrisType.semibold)),
                        const TextSpan(text: ' holiday pay'),
                        TextSpan(
                          text: '\nPaid on top of your day\'s pay, and only if you worked your last scheduled day before the '
                              'holiday (or were on paid leave).',
                          style: TextStyle(fontSize: HrisType.xs, color: t.text2),
                        ),
                      ] else ...[
                        TextSpan(text: ' · ${hoursLabel(preview.hours)} per date · about '),
                        TextSpan(text: Money.format(preview.estimatedPay), style: const TextStyle(fontWeight: HrisType.semibold)),
                        const TextSpan(text: ' each'),
                        TextSpan(
                          text: '\nYour shift ends at ${formatTimeOfDay(preview.scheduleEnd)}; the ${numText(preview.gapMinutes)}-minute '
                              'break after it is unpaid, so overtime starts at ${formatTimeOfDay(preview.earliestStart)}. '
                              'Paid only if you clock out at ${formatTimeOfDay(preview.endTime)} or later.',
                          style: TextStyle(fontSize: HrisType.xs, color: t.text2),
                        ),
                      ],
                    ]),
                    style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text),
                  ),
                ),
              ],
              if (_previewError.isNotEmpty) ...[
                const SizedBox(height: HrisSpace.s2),
                Text(_previewError, style: TextStyle(fontSize: HrisType.xs, height: 18 / 12, color: t.danger.text)),
              ],
              const SizedBox(height: HrisSpace.s4),

              OvertimeFormFilesField(
                holiday: holiday,
                files: _forms,
                pickers: widget.pickers,
                disabled: _submitting,
                error: _errors['attachment_url'],
                onChange: (f) => setState(() {
                  _forms = f;
                  _errors = {..._errors, 'attachment_url': null};
                }),
                onError: (msg) => setState(() => _errors = {..._errors, 'attachment_url': msg}),
              ),
              const SizedBox(height: HrisSpace.s4),

              TextField(
                key: const Key('ot_purpose'),
                controller: _purpose,
                minLines: 3,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  label: Text.rich(TextSpan(text: 'Purpose / justification', children: [
                    TextSpan(text: ' *', style: TextStyle(color: t.danger.solid)),
                  ])),
                  alignLabelWithHint: true,
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  helperText: 'Your approver decides on this, so say what the work is.',
                  helperMaxLines: 2,
                  errorText: _errors['purpose'],
                  errorMaxLines: 3,
                ),
                onChanged: (_) {
                  if (_errors['purpose'] != null) setState(() => _errors = {..._errors, 'purpose': null});
                },
              ),
            ],
          ),
        ),
      ),
      // The web dialog's footer: Cancel, then the primary action.
      bottomNavigationBar: SafeArea(
        child: Container(
          decoration: BoxDecoration(color: t.surface, border: Border(top: BorderSide(color: t.border))),
          padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s3, HrisSpace.s4, HrisSpace.s3),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: HrisSpace.s3),
              Expanded(
                flex: 2,
                child: FilledButton(
                  key: const Key('ot_submit'),
                  onPressed: _submitting || overCap ? null : _submit,
                  child: _submitting
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : Text(holiday ? 'File holiday work' : 'File overtime'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
