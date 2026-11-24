import 'package:flutter/material.dart';

import '../../core/http/api_exception.dart';
import '../../shared/button_styles.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/message_banner.dart';
import '../payslips/payslip_models.dart' show formatDateOnly;
import 'leave_api.dart';
import 'leave_models.dart';

/// FILE A LEAVE REQUEST — the web LeaveRequestDialog on the phone, as a page:
/// Leave type, Start date, End date, Day part (only for a one-day request),
/// Reason (optional). Same light checks as the web (the server re-validates and
/// is authoritative); `days` and `status` are derived by the server, never sent.
/// Pops `true` once submitted.
class LeaveRequestFormScreen extends StatefulWidget {
  final LeaveApi api;
  final List<LeaveType> types;

  const LeaveRequestFormScreen({super.key, required this.api, required this.types});

  static Future<bool?> open(BuildContext context, {required LeaveApi api, required List<LeaveType> types}) =>
      Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => LeaveRequestFormScreen(api: api, types: types)),
      );

  @override
  State<LeaveRequestFormScreen> createState() => _LeaveRequestFormScreenState();
}

class _LeaveRequestFormScreenState extends State<LeaveRequestFormScreen> {
  final _reason = TextEditingController();
  String _typeId = '';
  String _from = '';
  String _to = '';
  String _dayPart = 'full';
  Map<String, String> _errors = {};
  String? _formError;
  bool _submitting = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  /// A half-day is a property of ONE day (server rule, migration 036): the
  /// selector applies only while the range is a single date; a widened range
  /// silently falls back to a full-day request.
  bool get _singleDay => _from.isNotEmpty && _from == _to;
  String get _effectiveDayPart => _singleDay ? _dayPart : 'full';

  String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate(bool from) async {
    final now = DateTime.now();
    final current = DateTime.tryParse(from ? _from : (_to.isNotEmpty ? _to : _from)) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 5, 12, 31),
      helpText: from ? 'Start date' : 'End date',
    );
    if (picked == null) return;
    setState(() {
      if (from) {
        _from = _ymd(picked);
      } else {
        _to = _ymd(picked);
      }
    });
  }

  Future<void> _submit() async {
    setState(() {
      _errors = {};
      _formError = null;
    });
    final next = <String, String>{};
    if (_typeId.isEmpty) next['leave_type_id'] = 'Select a leave type.';
    if (_from.isEmpty) next['date_from'] = 'Select a start date.';
    if (_to.isEmpty) next['date_to'] = 'Select an end date.';
    if (_from.isNotEmpty && _to.isNotEmpty && _from.compareTo(_to) > 0) {
      next['date_to'] = 'End date cannot be before the start date.';
    }
    if (next.isNotEmpty) {
      setState(() => _errors = next);
      return;
    }

    setState(() => _submitting = true);
    try {
      final payload = <String, dynamic>{
        'leave_type_id': int.parse(_typeId),
        'date_from': _from,
        'date_to': _to,
        'day_part': _effectiveDayPart,
      };
      final reason = _reason.text.trim();
      if (reason.isNotEmpty) payload['reason'] = reason;
      await widget.api.submit(payload);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.fieldErrors.isNotEmpty) {
          _errors = e.fieldErrors;
        } else {
          _formError = e.message.isEmpty ? 'Could not submit the request.' : e.message;
        }
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);

    Widget requiredLabel(String text) => Text.rich(TextSpan(text: text, children: [
          TextSpan(text: ' *', style: TextStyle(color: t.danger.solid)),
        ]));

    Widget dateField(String key, String label, String value, VoidCallback onTap) => InkWell(
          key: Key('leave_$key'),
          onTap: _submitting ? null : onTap,
          borderRadius: BorderRadius.circular(HrisRadius.control),
          child: InputDecorator(
            isEmpty: value.isEmpty,
            decoration: InputDecoration(
              label: requiredLabel(label),
              errorText: _errors[key],
              errorMaxLines: 2,
              floatingLabelBehavior: FloatingLabelBehavior.always,
              suffixIcon: const Icon(Icons.calendar_today_outlined),
            ),
            child: Text(value.isEmpty ? 'Select a date' : formatDateOnly(value),
                style: TextStyle(fontSize: HrisType.md, color: value.isEmpty ? t.muted : t.text)),
          ),
        );

    // An unknown error key (e.g. `day_part`, `employee_id`, a balance message on
    // `days`) still has to be seen: the web shows the ones its fields know.
    final known = {'leave_type_id', 'date_from', 'date_to', 'day_part', 'reason'};
    final others = _errors.entries.where((e) => !known.contains(e.key)).map((e) => e.value).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('File a leave request')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s4, HrisSpace.s4, HrisSpace.s6),
          children: [
            Text(
              'Your request is submitted for approval. The number of days is calculated from the dates.',
              style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text2),
            ),
            const SizedBox(height: HrisSpace.s4),
            if (_formError != null) ...[
              MessageBanner.error(_formError!),
              const SizedBox(height: HrisSpace.s3),
            ],
            for (final o in others) ...[
              MessageBanner.error(o),
              const SizedBox(height: HrisSpace.s3),
            ],
            DropdownButtonFormField<String>(
              key: const Key('leave_type'),
              initialValue: _typeId,
              isExpanded: true,
              decoration: InputDecoration(
                label: requiredLabel('Leave type'),
                floatingLabelBehavior: FloatingLabelBehavior.always,
                errorText: _errors['leave_type_id'],
                errorMaxLines: 2,
              ),
              items: [
                DropdownMenuItem(value: '', child: Text('Select…', style: TextStyle(color: t.muted))),
                for (final ty in widget.types)
                  DropdownMenuItem(value: '${ty.id}', child: Text(ty.optionLabel, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: _submitting ? null : (v) => setState(() => _typeId = v ?? ''),
            ),
            const SizedBox(height: HrisSpace.s4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: dateField('date_from', 'Start date', _from, () => _pickDate(true))),
                const SizedBox(width: HrisSpace.s3),
                Expanded(child: dateField('date_to', 'End date', _to, () => _pickDate(false))),
              ],
            ),
            const SizedBox(height: HrisSpace.s4),
            DropdownButtonFormField<String>(
              // Keyed on the shown value so the fall-back to Full day is drawn.
              key: ValueKey('leave_day_part_$_effectiveDayPart$_singleDay'),
              initialValue: _effectiveDayPart,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Day part',
                floatingLabelBehavior: FloatingLabelBehavior.always,
                helperText: _singleDay
                    ? 'A morning/afternoon half files 0.5 day.'
                    : 'Half-day applies only when the start and end date are the same day.',
                helperMaxLines: 2,
                errorText: _errors['day_part'],
                errorMaxLines: 2,
              ),
              items: [
                for (final e in leaveDayPartLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: _submitting || !_singleDay ? null : (v) => setState(() => _dayPart = v ?? 'full'),
            ),
            const SizedBox(height: HrisSpace.s4),
            TextField(
              key: const Key('leave_reason'),
              controller: _reason,
              enabled: !_submitting,
              minLines: 3,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Reason',
                floatingLabelBehavior: FloatingLabelBehavior.always,
                helperText: 'Optional.',
                errorText: _errors['reason'],
                errorMaxLines: 2,
              ),
            ),
            const SizedBox(height: HrisSpace.s5),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FilledButton(
                  style: HrisButtonStyles.secondary(context),
                  onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: HrisSpace.s2),
                FilledButton(
                  key: const Key('leave_submit'),
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Submit request'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
