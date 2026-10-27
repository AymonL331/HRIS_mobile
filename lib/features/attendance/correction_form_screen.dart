import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/http/api_exception.dart';
import '../../core/time/manila_time.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/message_banner.dart';
import 'attendance_api.dart';

/// A picked proof photo: the bytes and the type the server will sniff again.
class PickedProof {
  final Uint8List bytes;
  final String mimeType;
  final String name;
  const PickedProof({required this.bytes, required this.mimeType, required this.name});
}

/// Opens the camera or the gallery. Null when the person backed out. The widget
/// tests pass a fake — they cannot open either.
typedef ProofPicker = Future<PickedProof?> Function(ImageSource source);

/// The camera refused: Android's runtime permission is not granted.
class ProofCameraDenied implements Exception {
  const ProofCameraDenied();
}

// Mirrors the server's accepted types (imageUpload.validator ALLOWED_MIME) and the
// 5 MB cap. Checked here only to fail fast — the server re-validates the bytes.
const _maxMb = 5;

/// The type from the first bytes (JPEG FF D8 FF, PNG 89 50 4E 47, GIF "GIF8",
/// WEBP "RIFF….WEBP"), never from the file name. Null = not one we accept.
String? sniffImageType(Uint8List b) {
  if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'image/jpeg';
  if (b.length > 4 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'image/png';
  if (b.length > 4 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x38) return 'image/gif';
  if (b.length > 12 && b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 && b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
    return 'image/webp';
  }
  return null;
}

/// The real picker: a CCTV screenshot or a gate-log photo usually sits in the
/// gallery, so both sources are offered (the profile photo is camera-only; this is
/// evidence, not a likeness). Capped at 1600 px / JPEG 85 to keep the upload small.
Future<PickedProof?> pickProofPhoto(ImageSource source) async {
  if (source == ImageSource.camera) {
    final status = await Permission.camera.request();
    if (!status.isGranted) throw const ProofCameraDenied();
  }
  final file = await ImagePicker().pickImage(
    source: source,
    maxWidth: 1600,
    maxHeight: 1600,
    imageQuality: 85,
    requestFullMetadata: false,
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  return PickedProof(bytes: bytes, mimeType: sniffImageType(bytes) ?? '', name: file.name);
}

/// Manila wall-clock date + "HH:MM" → the UTC "YYYY-MM-DD HH:MM" the API stores
/// (the web's localDateTimeToUtc, but always in Manila, never the phone's zone).
String manilaToUtcText(String date, TimeOfDay time) {
  final d = DateTime.parse(date);
  final utc = DateTime.utc(d.year, d.month, d.day, time.hour, time.minute).subtract(ManilaTime.offset);
  String p(int n) => n.toString().padLeft(2, '0');
  return '${utc.year}-${p(utc.month)}-${p(utc.day)} ${p(utc.hour)}:${p(utc.minute)}';
}

/// FILE A DTR CORRECTION (2026-10-27) — the web's CorrectionRequestDialog on the
/// phone, with the same rules: a date up to today, a corrected clock-in and/or
/// clock-out, a REQUIRED proof photo and a REQUIRED reason. The photo is staged
/// first; only when that succeeds is the request filed with its URL, so a request
/// never goes in without its evidence. It goes for approval before the DTR moves.
///
/// Pops `true` once filed.
class CorrectionFormScreen extends StatefulWidget {
  final AttendanceApi api;
  final String today; // Manila YYYY-MM-DD, the latest selectable day
  final String? initialDate;
  final ProofPicker picker;

  const CorrectionFormScreen({
    super.key,
    required this.api,
    required this.today,
    this.initialDate,
    this.picker = pickProofPhoto,
  });

  static Future<bool?> open(BuildContext context, {required AttendanceApi api, required String today, String? initialDate}) =>
      Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => CorrectionFormScreen(api: api, today: today, initialDate: initialDate)),
      );

  @override
  State<CorrectionFormScreen> createState() => _CorrectionFormScreenState();
}

class _CorrectionFormScreenState extends State<CorrectionFormScreen> {
  final _reason = TextEditingController();
  String? _date;
  TimeOfDay? _in;
  TimeOfDay? _out;
  PickedProof? _proof;
  Map<String, String> _errors = {};
  String? _formError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final last = DateTime.parse(widget.today);
    final current = DateTime.tryParse(_date ?? '') ?? last;
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isAfter(last) ? last : current,
      firstDate: DateTime(last.year - 1, 1, 1),
      // A correction states what DID happen — tomorrow is not selectable. Today
      // is: forgetting to clock in this morning is the ordinary reason to file.
      lastDate: last,
      helpText: 'Day to correct',
    );
    if (picked == null) return;
    setState(() {
      _date = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      _errors = {..._errors}..remove('date');
    });
  }

  Future<void> _pickTime(bool clockIn) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: (clockIn ? _in : _out) ?? (clockIn ? const TimeOfDay(hour: 8, minute: 0) : const TimeOfDay(hour: 17, minute: 0)),
      helpText: clockIn ? 'Corrected clock-in' : 'Corrected clock-out',
    );
    if (picked == null) return;
    setState(() {
      if (clockIn) {
        _in = picked;
      } else {
        _out = picked;
      }
      _errors = {..._errors}
        ..remove('clock_in')
        ..remove('clock_out');
    });
  }

  Future<void> _chooseProof() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              subtitle: const Text('A CCTV screenshot or a saved photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            const SizedBox(height: HrisSpace.s2),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final picked = await widget.picker(source);
      if (picked == null || !mounted) return;
      String? problem;
      if (picked.mimeType.isEmpty) {
        problem = 'Unsupported image. Use JPEG, PNG, WEBP, or GIF.';
      } else if (picked.bytes.length > _maxMb * 1024 * 1024) {
        problem = 'That image is too large. Maximum size is $_maxMb MB.';
      }
      setState(() {
        if (problem != null) {
          _errors = {..._errors, 'proof': problem};
        } else {
          _proof = picked;
          _errors = {..._errors}..remove('proof');
        }
      });
    } on ProofCameraDenied {
      if (!mounted) return;
      setState(() => _errors = {..._errors, 'proof': 'Camera permission is off. Allow it in Settings, or choose from the gallery.'});
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final reason = _reason.text.trim();
    final local = <String, String>{
      if (_date == null) 'date': 'Select the date to correct.',
      if (_in == null && _out == null) 'clock_in': 'Enter a corrected clock-in and/or clock-out.',
      if (reason.isEmpty) 'reason': 'Explain why you were not able to clock out.',
      if (_proof == null) 'proof': 'Attach a photo proving you were at the office.',
    };
    setState(() {
      _errors = local;
      _formError = null;
    });
    if (local.isNotEmpty) return;

    setState(() => _busy = true);
    try {
      // 1) Stage the photo. A failure here must NOT leave a request without its
      //    evidence, so the correction is filed only once this succeeds.
      final url = await widget.api.stageProof(bytes: _proof!.bytes, mimeType: _proof!.mimeType, name: _proof!.name);
      if (url.isEmpty) throw const ApiException(status: 0, message: 'The proof photo could not be uploaded. Please try again.');
      // 2) File it, carrying only the stored URL. employee_id is forced to me on the server.
      await widget.api.submitCorrection({
        'date': _date,
        'reason': reason,
        'proof_photo_url': url,
        if (_in != null) 'requested_clock_in': manilaToUtcText(_date!, _in!),
        if (_out != null) 'requested_clock_out': manilaToUtcText(_date!, _out!),
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.fieldErrors.isNotEmpty) {
          final f = e.fieldErrors;
          _errors = {
            if (f['date'] != null) 'date': f['date']!,
            if (f['requested_clock_in'] != null) 'clock_in': f['requested_clock_in']!,
            if (f['requested_clock_out'] != null) 'clock_out': f['requested_clock_out']!,
            if (f['reason'] != null) 'reason': f['reason']!,
            // The staging route names its fields type / data / file.
            if ((f['proof_photo_url'] ?? f['type'] ?? f['data'] ?? f['file']) != null)
              'proof': (f['proof_photo_url'] ?? f['type'] ?? f['data'] ?? f['file'])!,
          };
          if (_errors.isEmpty) _formError = f.values.first;
        } else {
          _formError = e.message;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final hintStyle = TextStyle(fontSize: HrisType.xs, height: 18 / 12, color: t.text2);

    // A tappable field drawn as the theme's input (label, border, error) — the
    // web's date / time inputs.
    Widget pickerField({
      required String label,
      required String? value,
      required String placeholder,
      required IconData icon,
      required VoidCallback onTap,
      String? error,
      VoidCallback? onClear,
      bool required = false,
    }) =>
        InkWell(
          onTap: _busy ? null : onTap,
          borderRadius: BorderRadius.circular(HrisRadius.control),
          child: InputDecorator(
            isEmpty: value == null,
            decoration: InputDecoration(
              label: Text.rich(TextSpan(text: label, children: [
                if (required) TextSpan(text: ' *', style: TextStyle(color: t.danger.solid)),
              ])),
              // No hintText: the child below already shows the placeholder (both
              // drew on top of each other — "Select a date" twice, 2026-10-27).
              errorText: error,
              floatingLabelBehavior: FloatingLabelBehavior.always,
              suffixIcon: value != null && onClear != null
                  ? IconButton(tooltip: 'Clear $label', icon: const Icon(Icons.close), onPressed: _busy ? null : onClear)
                  : Icon(icon),
            ),
            child: Text(value ?? placeholder, style: TextStyle(fontSize: HrisType.md, color: value == null ? t.muted : t.text)),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('File a DTR correction')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s4, HrisSpace.s4, HrisSpace.s6),
          children: [
            Text(
              'Request a fix to your time record for a day. Enter the corrected clock-in and/or clock-out, '
              'attach proof that you were at the office, and say why you were not able to clock out. '
              'It goes for approval before your record is updated.',
              style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text2),
            ),
            const SizedBox(height: HrisSpace.s4),
            if (_formError != null) ...[
              MessageBanner.error(_formError!),
              const SizedBox(height: HrisSpace.s3),
            ],
            pickerField(
              label: 'Date',
              required: true,
              value: _date == null ? null : ManilaTime.dateOnly(_date!),
              placeholder: 'Select a date',
              icon: Icons.calendar_today_outlined,
              onTap: _pickDate,
              error: _errors['date'],
            ),
            const SizedBox(height: HrisSpace.s4),
            pickerField(
              label: 'Corrected clock-in',
              value: _in?.format(context),
              placeholder: 'Not changed',
              icon: Icons.schedule,
              onTap: () => _pickTime(true),
              onClear: () => setState(() => _in = null),
              error: _errors['clock_in'],
            ),
            const SizedBox(height: HrisSpace.s4),
            pickerField(
              label: 'Corrected clock-out',
              value: _out?.format(context),
              placeholder: 'Not changed',
              icon: Icons.schedule,
              onTap: () => _pickTime(false),
              onClear: () => setState(() => _out = null),
              error: _errors['clock_out'],
            ),
            const SizedBox(height: HrisSpace.s5),

            // Proof photo — required evidence (migration 024).
            Text.rich(
              TextSpan(text: 'Proof photo', children: [TextSpan(text: ' *', style: TextStyle(color: t.danger.solid))]),
              style: TextStyle(fontSize: HrisType.sm, fontWeight: HrisType.medium, height: 20 / 14, color: t.text),
            ),
            const SizedBox(height: HrisSpace.s1),
            Text(
              'A CCTV screenshot, gate or door log, or a photo at your workstation that shows you were at the '
              'office that day. JPEG, PNG, WEBP or GIF, up to $_maxMb MB.',
              style: hintStyle,
            ),
            const SizedBox(height: HrisSpace.s2),
            if (_proof != null)
              Container(
                decoration: BoxDecoration(
                  color: t.surface,
                  border: Border.all(color: t.border),
                  borderRadius: BorderRadius.circular(HrisRadius.panel),
                ),
                padding: const EdgeInsets.all(HrisSpace.s2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(HrisRadius.control),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: Image.memory(
                          _proof!.bytes,
                          fit: BoxFit.contain,
                          semanticLabel: 'The selected proof photo',
                          // A file the phone cannot draw still uploads; the server judges it.
                          errorBuilder: (_, _, _) => SizedBox(
                            height: 96,
                            child: Center(child: Icon(Icons.image_outlined, size: 40, color: t.muted)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: HrisSpace.s2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(_proof!.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: hintStyle),
                        ),
                        OutlinedButton(onPressed: _busy ? null : () => setState(() => _proof = null), child: const Text('Remove')),
                      ],
                    ),
                  ],
                ),
              )
            else
              OutlinedButton(onPressed: _busy ? null : _chooseProof, child: const Text('Choose photo')),
            if (_errors['proof'] != null) ...[
              const SizedBox(height: HrisSpace.s1),
              Text(_errors['proof']!, style: TextStyle(fontSize: HrisType.xs, height: 18 / 12, color: t.danger.text)),
            ],
            const SizedBox(height: HrisSpace.s5),

            TextField(
              controller: _reason,
              enabled: !_busy,
              minLines: 3,
              maxLines: 5,
              maxLength: 255,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                label: Text.rich(TextSpan(text: 'Reason', children: [
                  TextSpan(text: ' *', style: TextStyle(color: t.danger.solid)),
                ])),
                alignLabelWithHint: true,
                floatingLabelBehavior: FloatingLabelBehavior.always,
                helperText: 'Required. Explain why you were not able to clock out — e.g. the terminal was down when I left at 6:00 PM.',
                helperMaxLines: 3,
                errorText: _errors['reason'],
                errorMaxLines: 3,
              ),
              onChanged: (_) {
                if (_errors.containsKey('reason')) setState(() => _errors = {..._errors}..remove('reason'));
              },
            ),
          ],
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
                  onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: HrisSpace.s3),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : const Text('Submit correction'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
