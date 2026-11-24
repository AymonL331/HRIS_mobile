import 'package:flutter/material.dart';

import '../../core/http/api_exception.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/message_banner.dart';
import '../attendance/correction_form_screen.dart' show PickedProof;
import 'overtime_api.dart';
import 'overtime_files.dart';
import 'overtime_models.dart';

/// Add the requirements to holiday work / overtime my admin SET for me
/// (migration 122) — the web's OvertimeRequirementsDialog. Already approved; this
/// only completes the paperwork: the approved form (required for holiday work
/// with none on file, optional for overtime) and my remarks. New files are ADDED
/// to what is there, up to 5 in all. Pops `true` once saved.
class OvertimeRequirementsScreen extends StatefulWidget {
  final OvertimeApi api;
  final OvertimeRequest request;
  final OvertimePickers pickers;

  const OvertimeRequirementsScreen({
    super.key,
    required this.api,
    required this.request,
    this.pickers = const OvertimePickers(),
  });

  static Future<bool?> open(
    BuildContext context, {
    required OvertimeApi api,
    required OvertimeRequest request,
    OvertimePickers pickers = const OvertimePickers(),
  }) =>
      Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => OvertimeRequirementsScreen(api: api, request: request, pickers: pickers)),
      );

  @override
  State<OvertimeRequirementsScreen> createState() => _OvertimeRequirementsScreenState();
}

class _OvertimeRequirementsScreenState extends State<OvertimeRequirementsScreen> {
  late final TextEditingController _purpose = TextEditingController(text: widget.request.purpose ?? '');
  List<PickedProof> _files = [];
  String? _fileError;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _purpose.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _purpose.dispose();
    super.dispose();
  }

  OvertimeRequest get r => widget.request;
  List<String> get _attached => r.files;
  bool get _hasForm => _attached.isNotEmpty;
  bool get _canSave => !_busy && _purpose.text.trim().isNotEmpty && (!r.holiday || _hasForm || _files.isNotEmpty);

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final urls = <String>[];
      for (final f in _files) {
        final url = await widget.api.stageForm(f);
        if (url.isEmpty) throw const ApiException(status: 0, message: 'A file could not be uploaded. Please try again.');
        urls.add(url);
      }
      // Kept first file stays first; new ones are added after it.
      final first = r.attachmentUrl ?? (urls.isNotEmpty ? urls.first : null);
      final more = r.attachmentUrl != null ? urls : (urls.length > 1 ? urls.sublist(1) : const <String>[]);
      await widget.api.completeRequirements(r.id, {
        'purpose': _purpose.text.trim(),
        'attachment_url': ?first,
        if (more.isNotEmpty) 'more_attachment_urls': more,
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message.isNotEmpty ? e.message : 'Could not save. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final days = r.dates.map((d) => formatDateOnly(d.date)).join(', ');
    return Scaffold(
      appBar: AppBar(title: Text(r.holiday ? 'Add the approved form and remarks' : 'Add your remarks')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s4, HrisSpace.s4, HrisSpace.s6),
          children: [
            Text(
              '${r.holiday ? 'Holiday work' : 'Overtime'} on $days — set by ${r.assignedByName ?? 'your admin'} and already approved.',
              style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text2),
            ),
            const SizedBox(height: HrisSpace.s4),
            if (_hasForm) ...[
              Text(
                '${_attached.length == 1 ? 'A file is' : '${_attached.length} files are'} already attached. Files you add here are added to them.',
                style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text),
              ),
              const SizedBox(height: HrisSpace.s3),
            ],
            OvertimeFormFilesField(
              files: _files,
              onChange: (f) => setState(() => _files = f),
              error: _fileError,
              onError: (m) => setState(() => _fileError = m),
              disabled: _busy,
              holiday: r.holiday && !_hasForm,
              max: (maxFormFiles - _attached.length).clamp(0, maxFormFiles),
              pickers: widget.pickers,
            ),
            const SizedBox(height: HrisSpace.s4),
            TextField(
              key: const Key('ot_req_purpose'),
              controller: _purpose,
              enabled: !_busy,
              minLines: 3,
              maxLines: 5,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                label: Text.rich(TextSpan(text: 'Remarks', children: [
                  TextSpan(text: ' *', style: TextStyle(color: t.danger.solid)),
                ])),
                alignLabelWithHint: true,
                floatingLabelBehavior: FloatingLabelBehavior.always,
                helperText: 'What you worked on that day.',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: HrisSpace.s2),
              MessageBanner.error(_error!),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          decoration: BoxDecoration(color: t.surface, border: Border(top: BorderSide(color: t.border))),
          padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s3, HrisSpace.s4, HrisSpace.s3),
          child: Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: HrisSpace.s3),
              Expanded(
                flex: 2,
                child: FilledButton(
                  key: const Key('ot_req_save'),
                  onPressed: _canSave ? _save : null,
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
