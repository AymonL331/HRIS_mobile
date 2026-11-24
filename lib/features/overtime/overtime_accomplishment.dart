import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/http/api_exception.dart';
import '../../shared/tokens.dart';
import '../attendance/correction_form_screen.dart' show PickedProof, ProofPicker, ProofCameraDenied;
import 'overtime_api.dart';
import 'overtime_files.dart';
import 'overtime_models.dart';

const _photoTypes = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'];

BoxDecoration _panel(HrisTokens t) => BoxDecoration(
      color: t.surfaceSunken,
      border: Border.all(color: t.border),
      borderRadius: BorderRadius.circular(HrisRadius.control),
    );

/// Report what was accomplished on ONE approved overtime date — the web's
/// OvertimeAccomplishmentForm, opened INLINE under the row that was tapped.
/// Remarks AND at least one picture (up to 12) — both needed (user 2026-11-24).
/// Submitting is final.
class OvertimeAccomplishmentForm extends StatefulWidget {
  final OvertimeApi api;
  final OvertimeDate dateRow;
  final ProofPicker picker;
  final VoidCallback onCancel;
  final VoidCallback onSubmitted;

  const OvertimeAccomplishmentForm({
    super.key,
    required this.api,
    required this.dateRow,
    required this.picker,
    required this.onCancel,
    required this.onSubmitted,
  });

  @override
  State<OvertimeAccomplishmentForm> createState() => _OvertimeAccomplishmentFormState();
}

class _OvertimeAccomplishmentFormState extends State<OvertimeAccomplishmentForm> {
  final _note = TextEditingController();
  final List<PickedProof> _pending = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _note.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  int get _remaining => (maxAccomplishmentPhotos - _pending.length).clamp(0, maxAccomplishmentPhotos);
  bool get _canSubmit => _note.text.trim().isNotEmpty && _pending.isNotEmpty;

  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _addPicture() async {
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
      if (!_photoTypes.contains(picked.mimeType)) {
        _toast('Unsupported image. Use JPEG, PNG, WEBP, or GIF.');
        return;
      }
      if (_remaining < 1) return;
      setState(() => _pending.add(picked));
    } on ProofCameraDenied {
      if (mounted) _toast('Camera permission is off. Allow it in Settings, or choose from the gallery.');
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _saving = true);
    try {
      final note = _note.text.trim();
      await widget.api.submitAccomplishment(widget.dateRow.id, note: note.isEmpty ? null : note, photos: List.of(_pending));
      if (!mounted) return;
      _toast('Accomplishment recorded.');
      widget.onSubmitted();
    } on ApiException catch (e) {
      if (mounted) _toast(e.message.isNotEmpty ? e.message : 'Could not record the accomplishment.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final d = widget.dateRow;
    return Container(
      margin: const EdgeInsets.only(top: HrisSpace.s2),
      padding: const EdgeInsets.all(HrisSpace.s3),
      decoration: _panel(t),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('What did you accomplish on ${formatDateOnly(d.date)}?',
              style: TextStyle(fontSize: HrisType.sm, fontWeight: HrisType.semibold, height: 20 / 14, color: t.text)),
          const SizedBox(height: HrisSpace.s3),
          TextField(
            key: const Key('ot_accomplishment_note'),
            controller: _note,
            enabled: !_saving,
            minLines: 3,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Accomplishment remarks *',
              alignLabelWithHint: true,
              floatingLabelBehavior: FloatingLabelBehavior.always,
              helperText: 'Describe the work you completed during the approved overtime.',
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: HrisSpace.s3),
          Text.rich(
            TextSpan(text: 'Add pictures ', children: [
              TextSpan(
                text: '(at least 1 · $_remaining more allowed)',
                style: TextStyle(fontWeight: FontWeight.normal, color: t.muted, fontSize: HrisType.xs),
              ),
            ]),
            style: TextStyle(fontSize: HrisType.sm, fontWeight: HrisType.medium, color: t.text),
          ),
          const SizedBox(height: HrisSpace.s2),
          if (_pending.isNotEmpty) ...[
            Wrap(
              spacing: HrisSpace.s2,
              runSpacing: HrisSpace.s2,
              children: [
                for (var i = 0; i < _pending.length; i++)
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(HrisRadius.control),
                        child: Image.memory(
                          _pending[i].bytes,
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                          semanticLabel: _pending[i].name,
                          errorBuilder: (_, _, _) => Container(
                            width: 72,
                            height: 72,
                            color: t.surface,
                            child: Icon(Icons.image_outlined, color: t.muted),
                          ),
                        ),
                      ),
                      Positioned(
                        right: -8,
                        top: -8,
                        child: IconButton.filledTonal(
                          tooltip: 'Remove ${_pending[i].name}',
                          visualDensity: VisualDensity.compact,
                          iconSize: 16,
                          onPressed: _saving ? null : () => setState(() => _pending.removeAt(i)),
                          icon: const Icon(Icons.close),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: HrisSpace.s2),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _saving || _remaining == 0 ? null : _addPicture,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Add picture'),
            ),
          ),
          const SizedBox(height: HrisSpace.s3),
          // Said BEFORE the button, at the last point anything can still change.
          Text(
            'Remarks and at least one picture are both needed. Once submitted, this report can no longer be edited — check them before sending.',
            style: TextStyle(fontSize: HrisType.xs, height: 18 / 12, color: t.warning.text),
          ),
          const SizedBox(height: HrisSpace.s3),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(onPressed: _saving ? null : widget.onCancel, child: const Text('Cancel')),
              const SizedBox(width: HrisSpace.s2),
              FilledButton(
                key: const Key('ot_accomplishment_submit'),
                onPressed: _saving || !_canSubmit ? null : _submit,
                child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Submit'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A SUBMITTED accomplishment, read-only (OvertimeAccomplishmentView).
class OvertimeAccomplishmentView extends StatelessWidget {
  final OvertimeDate dateRow;
  final String baseUrl;
  final VoidCallback onClose;

  const OvertimeAccomplishmentView({super.key, required this.dateRow, required this.baseUrl, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final d = dateRow;
    return Container(
      margin: const EdgeInsets.only(top: HrisSpace.s2),
      padding: const EdgeInsets.all(HrisSpace.s3),
      decoration: _panel(t),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Accomplishment for ${formatDateOnly(d.date)}',
              style: TextStyle(fontSize: HrisType.sm, fontWeight: HrisType.semibold, height: 20 / 14, color: t.text)),
          const SizedBox(height: 2),
          Text('Submitted ${formatDateTime(d.accomplishmentAt)} · final',
              style: TextStyle(fontSize: HrisType.xs, height: 18 / 12, color: t.muted)),
          const SizedBox(height: HrisSpace.s2),
          d.accomplishmentNote != null
              ? Text(d.accomplishmentNote!, style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text))
              : Text('No remarks were written for this date.', style: TextStyle(fontSize: HrisType.sm, color: t.muted)),
          if (d.photos.isNotEmpty) ...[
            const SizedBox(height: HrisSpace.s3),
            Text('Pictures', style: TextStyle(fontSize: HrisType.sm, fontWeight: HrisType.medium, color: t.text)),
            const SizedBox(height: HrisSpace.s2),
            OvertimeThumbs(
              urls: d.photos.map((p) => p.fileUrl).toList(),
              baseUrl: baseUrl,
              alt: 'Submitted accomplishment',
              size: 72,
            ),
          ],
          const SizedBox(height: HrisSpace.s3),
          Align(alignment: Alignment.centerRight, child: OutlinedButton(onPressed: onClose, child: const Text('Close'))),
        ],
      ),
    );
  }
}
