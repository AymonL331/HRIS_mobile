import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../shared/tokens.dart';
import '../attendance/correction_form_screen.dart' show PickedProof, ProofPicker, ProofCameraDenied, pickProofPhoto;
import 'overtime_models.dart';

/// Picks a scanned PDF of the approved form. Null when the person backed out.
typedef OvertimePdfPicker = Future<PickedProof?> Function();

Future<PickedProof?> pickOvertimePdf() async {
  final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf']);
  if (files.isEmpty) return null;
  final f = files.first;
  return PickedProof(bytes: await f.readAsBytes(), mimeType: 'application/pdf', name: f.name);
}

/// The pickers a screen uses — injectable so the widget tests can stand in.
class OvertimePickers {
  final ProofPicker photo;
  final OvertimePdfPicker pdf;
  const OvertimePickers({this.photo = pickProofPhoto, this.pdf = pickOvertimePdf});
}

const _formTypes = ['image/jpeg', 'image/png', 'application/pdf'];

/// HolidayWorkFormField — the management-approved HOLIDAY WORK / OVERTIME form:
/// pictures (JPG or PNG) or scanned PDFs, up to [max] files, 10 MB each. Required
/// on a holiday ([holiday] true), optional for ordinary overtime. Holds the picked
/// files; the screen stages them on submit.
class OvertimeFormFilesField extends StatelessWidget {
  final List<PickedProof> files;
  final ValueChanged<List<PickedProof>> onChange;
  final String? error;
  final ValueChanged<String?> onError;
  final bool disabled;
  final bool holiday;
  final int max;
  final OvertimePickers pickers;

  const OvertimeFormFilesField({
    super.key,
    required this.files,
    required this.onChange,
    required this.onError,
    this.error,
    this.disabled = false,
    this.holiday = true,
    this.max = maxFormFiles,
    this.pickers = const OvertimePickers(),
  });

  int get _room => (max - files.length).clamp(0, max);

  Future<void> _choose(BuildContext context) async {
    final source = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              subtitle: const Text('A photo or scan of the approved form'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Choose a PDF'),
              subtitle: const Text('A scanned copy of the approved form'),
              onTap: () => Navigator.pop(ctx, 'pdf'),
            ),
            const SizedBox(height: HrisSpace.s2),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final picked = source == 'pdf' ? await pickers.pdf() : await pickers.photo(source as ImageSource);
      if (picked == null) return;
      // The web's checks, in its words. The server sniffs the bytes again.
      if (!_formTypes.contains(picked.mimeType)) {
        onError('Attach the approved form as a picture (JPG or PNG) or a PDF.');
        return;
      }
      if (picked.bytes.length > maxFormFileMb * 1024 * 1024) {
        onError('A file is too large. Maximum size is $maxFormFileMb MB each.');
        return;
      }
      if (_room < 1) {
        onError('You can attach up to $max files.');
        return;
      }
      onError(null);
      onChange([...files, picked]);
    } on ProofCameraDenied {
      onError('Camera permission is off. Allow it in Settings, or choose from the gallery.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final hintStyle = TextStyle(fontSize: HrisType.xs, height: 18 / 12, color: t.text2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: holiday ? 'Approved holiday work form ' : 'Approved overtime form ',
            children: [
              holiday
                  ? TextSpan(text: '*', style: TextStyle(color: t.danger.solid))
                  : TextSpan(text: '(optional)', style: hintStyle.copyWith(fontWeight: FontWeight.normal)),
            ],
          ),
          style: TextStyle(fontSize: HrisType.sm, fontWeight: HrisType.medium, height: 20 / 14, color: t.text),
        ),
        const SizedBox(height: HrisSpace.s1),
        Text(
          '${holiday ? 'The holiday work form signed by management' : 'The overtime form signed by your approver, if you have one'} — '
          'pictures (JPG or PNG) or scanned PDFs, up to $max files, $maxFormFileMb MB each.',
          style: hintStyle,
        ),
        const SizedBox(height: HrisSpace.s2),
        for (var i = 0; i < files.length; i++) ...[
          _FileTile(
            file: files[i],
            disabled: disabled,
            onRemove: () => onChange([...files]..removeAt(i)),
          ),
          const SizedBox(height: HrisSpace.s2),
        ],
        if (_room > 0)
          OutlinedButton(
            onPressed: disabled ? null : () => _choose(context),
            child: Text(files.isNotEmpty ? 'Add another file' : 'Choose files'),
          ),
        if (error != null) ...[
          const SizedBox(height: HrisSpace.s1),
          Text(error!, style: TextStyle(fontSize: HrisType.xs, height: 18 / 12, color: t.danger.text)),
        ],
      ],
    );
  }
}

class _FileTile extends StatelessWidget {
  final PickedProof file;
  final VoidCallback onRemove;
  final bool disabled;

  const _FileTile({required this.file, required this.onRemove, required this.disabled});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final isPdf = file.mimeType == 'application/pdf';
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(HrisRadius.panel),
      ),
      padding: const EdgeInsets.all(HrisSpace.s2),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: isPdf
                ? const PdfTile(size: 56)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(HrisRadius.control),
                    child: Image.memory(
                      file.bytes,
                      fit: BoxFit.cover,
                      semanticLabel: 'Selected file ${file.name}',
                      errorBuilder: (_, _, _) => Icon(Icons.image_outlined, color: t.muted),
                    ),
                  ),
          ),
          const SizedBox(width: HrisSpace.s3),
          Expanded(
            child: Text(
              file.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: HrisType.xs, height: 18 / 12, color: t.text2),
            ),
          ),
          OutlinedButton(onPressed: disabled ? null : onRemove, child: const Text('Remove')),
        ],
      ),
    );
  }
}

/// ThumbLink's PDF tile: no image to show, so the tile says what it is.
class PdfTile extends StatelessWidget {
  final double size;
  const PdfTile({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(HrisRadius.control),
      ),
      child: Text('PDF',
          style: TextStyle(fontFamily: HrisFont.mono, fontSize: HrisType.xs, fontWeight: HrisType.semibold, color: t.text2)),
    );
  }
}

/// ThumbLinks: stored files as small thumbnails that open full size, or
/// [emptyLabel] when there are none. A PDF shows as a "PDF" tile.
class OvertimeThumbs extends StatelessWidget {
  final List<String> urls;
  final String baseUrl;
  final String alt;
  final String emptyLabel;
  final double size;

  const OvertimeThumbs({
    super.key,
    required this.urls,
    required this.baseUrl,
    required this.alt,
    this.emptyLabel = 'No proof',
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    if (urls.isEmpty) return Text(emptyLabel, style: TextStyle(fontSize: HrisType.xs, color: t.muted));
    return Wrap(
      spacing: HrisSpace.s1,
      runSpacing: HrisSpace.s1,
      children: [
        for (final url in urls)
          InkWell(
            onTap: () => openOvertimeFile(context, baseUrl: baseUrl, url: url, alt: alt),
            borderRadius: BorderRadius.circular(HrisRadius.control),
            child: RegExp(r'\.pdf$', caseSensitive: false).hasMatch(url)
                ? Semantics(label: alt, child: PdfTile(size: size))
                : NetworkThumb(url: '$baseUrl$url', size: size, alt: alt),
          ),
      ],
    );
  }
}

class NetworkThumb extends StatelessWidget {
  final String url;
  final double size;
  final String alt;
  const NetworkThumb({super.key, required this.url, required this.size, required this.alt});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(HrisRadius.control),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(HrisRadius.control - 1),
        child: Image.network(
          url,
          fit: BoxFit.cover,
          semanticLabel: alt,
          errorBuilder: (_, _, _) => Icon(Icons.image_outlined, size: size / 2, color: t.muted),
        ),
      ),
    );
  }
}

/// Opens a stored file full size. A picture opens in a zoomable viewer; a PDF
/// cannot be drawn by the app, so the person is told where to open it.
Future<void> openOvertimeFile(BuildContext context, {required String baseUrl, required String url, required String alt}) async {
  if (RegExp(r'\.pdf$', caseSensitive: false).hasMatch(url)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This form is a PDF. Open it on the ATLAS website to view it.')),
    );
    return;
  }
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => Scaffold(
      appBar: AppBar(title: Text(alt)),
      backgroundColor: Colors.black,
      body: Center(
        child: InteractiveViewer(
          child: Image.network('$baseUrl$url', fit: BoxFit.contain, semanticLabel: alt),
        ),
      ),
    ),
  ));
}
