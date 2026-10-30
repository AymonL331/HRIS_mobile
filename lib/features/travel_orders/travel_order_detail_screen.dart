import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/http/api_exception.dart';
import '../../core/location/location_fix.dart';
import '../../core/time/manila_time.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/kit.dart';
import '../../shared/widgets/message_banner.dart';
import '../../shared/widgets/status_badge.dart';
import '../attendance/correction_form_screen.dart' show PickedProof, ProofPicker, ProofCameraDenied, pickProofPhoto, sniffImageType;
import 'travel_order_api.dart';
import 'travel_order_models.dart';

/// Opens the camera (one photo) or the gallery (several). Empty when the person
/// backed out. Tests pass a fake.
typedef TripPhotoPicker = Future<List<PickedProof>> Function(ImageSource source);

/// The real picker: proof is usually taken on the spot, but a stop's photos are
/// often already in the gallery, so both are offered; the gallery allows several
/// at once (the server takes up to 12 per upload). Same 1600 px / JPEG 85 cap.
Future<List<PickedProof>> pickTripPhotos(ImageSource source, {ProofPicker single = pickProofPhoto}) async {
  if (source == ImageSource.camera) {
    final one = await single(source);
    return one == null ? const [] : [one];
  }
  final files = await ImagePicker().pickMultiImage(maxWidth: 1600, maxHeight: 1600, imageQuality: 85, limit: 12, requestFullMetadata: false);
  final out = <PickedProof>[];
  for (final f in files) {
    final bytes = await f.readAsBytes();
    out.add(PickedProof(bytes: bytes, mimeType: sniffImageType(bytes) ?? '', name: f.name));
  }
  return out;
}

/// ONE TRAVEL ORDER (2026-10-29) — the web track panel on the phone: the stops in
/// order with "Check in here" on the next one (a fresh GPS reading), the proof
/// photos per stop ($toMinPhotos each), the completion remarks, and the checklist
/// that tells me what is still missing before my approver can mark it completed.
/// A pending order can be cancelled. Same server calls and locks as the web.
class TravelOrderDetailScreen extends StatefulWidget {
  final TravelOrderApi api;
  final int id;
  final LocationFixService fixes;
  final String baseUrl;
  final TripPhotoPicker photoPicker;

  const TravelOrderDetailScreen({
    super.key,
    required this.api,
    required this.id,
    required this.fixes,
    required this.baseUrl,
    this.photoPicker = pickTripPhotos,
  });

  static Future<void> open(BuildContext context,
      {required TravelOrderApi api,
      required int id,
      required LocationFixService fixes,
      required String baseUrl,
      ProofPicker picker = pickProofPhoto}) {
    return Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TravelOrderDetailScreen(
        api: api,
        id: id,
        fixes: fixes,
        baseUrl: baseUrl,
        photoPicker: (source) => pickTripPhotos(source, single: picker),
      ),
    ));
  }

  @override
  State<TravelOrderDetailScreen> createState() => _TravelOrderDetailScreenState();
}

class _TravelOrderDetailScreenState extends State<TravelOrderDetailScreen> {
  final _remarks = TextEditingController();
  TravelOrderDetail? _detail;
  String? _loadError;
  String? _error;
  String? _ok;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await widget.api.detail(widget.id);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _loadError = null;
        _remarks.text = d.completionRemarks;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    }
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() {
      _busy = true;
      _error = null;
      _ok = null;
    });
    try {
      await action();
      await _load();
      if (mounted) setState(() => _ok = done);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.fieldErrors.isNotEmpty ? e.fieldErrors.values.first : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkIn(TravelStop stop) async {
    setState(() {
      _busy = true;
      _error = null;
      _ok = null;
    });
    void fail(String message) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = message;
        });
      }
    }

    LocationFix fix;
    try {
      fix = await widget.fixes.acquire();
    } on FixTimeout {
      return fail('Could not read your location — try again.');
    } catch (_) {
      return fail('Could not read your location — check that location is on.');
    }
    final check = validateFix(fix);
    if (check is FixMocked) return fail('Your phone reported a mock location. Turn it off and try again.');
    if (check is FixTooCoarse) {
      return fail('Your location is too rough (${check.accuracyM.round()} m). Step outside or wait a moment, then try again.');
    }
    await _run(
      () => widget.api.arrive(widget.id, destId: stop.id, lat: fix.latitude, lng: fix.longitude),
      'Checked in at ${stop.name}.',
    );
  }

  Future<void> _addPhotos(TravelStop stop) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              subtitle: const Text('You can pick several'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: HrisSpace.s2),
          ],
        ),
      ),
    );
    if (source == null) return;
    List<PickedProof> photos;
    try {
      photos = await widget.photoPicker(source);
    } on ProofCameraDenied {
      if (mounted) setState(() => _error = 'Camera permission is off. Allow it in Settings, or choose from the gallery.');
      return;
    }
    if (photos.isEmpty || !mounted) return;
    if (photos.any((p) => p.mimeType.isEmpty)) {
      setState(() => _error = 'Unsupported image. Use JPEG, PNG, WEBP, or GIF.');
      return;
    }
    if (photos.any((p) => p.bytes.length > 5 * 1024 * 1024)) {
      setState(() => _error = 'An image is too large. Maximum size is 5 MB each.');
      return;
    }
    final remarks = _remarks.text.trim();
    await _run(
      // The trip narrative rides along when it has text, as on the web.
      () => widget.api.addProof(widget.id, destId: stop.id, photos: photos, completionRemarks: remarks.isEmpty ? null : remarks),
      photos.length == 1 ? 'Photo uploaded.' : '${photos.length} photos uploaded.',
    );
  }

  Future<void> _saveRemarks() async {
    FocusScope.of(context).unfocus();
    await _run(() => widget.api.addProof(widget.id, completionRemarks: _remarks.text.trim()), 'Remarks saved.');
  }

  Future<void> _cancel(TravelOrderDetail d) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this Travel Order?'),
        content: Text("${d.toNumber} — ${d.purpose}. This can't be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel it')),
        ],
      ),
    );
    if (yes != true) return;
    await _run(() => widget.api.cancel(d.id), 'Travel Order cancelled.');
  }

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final d = _detail;
    final meta = TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text2);

    Widget body;
    if (d == null && _loadError != null) {
      body = Padding(
        padding: const EdgeInsets.all(HrisSpace.s4),
        child: StatePanel(
          title: "Couldn't load the travel order",
          message: _loadError,
          error: true,
          action: OutlinedButton(onPressed: _load, child: const Text('Try again')),
        ),
      );
    } else if (d == null) {
      body = const LoadingBlock(semanticsLabel: 'Loading the travel order');
    } else {
      final approved = d.status == 'approved';
      final locked = d.remarksLocked;
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s4, HrisSpace.s4, HrisSpace.s6),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(d.toNumber,
                      style: TextStyle(fontFamily: HrisFont.mono, fontSize: HrisType.sm, color: t.text2)),
                ),
                StatusBadge(toStatusLabel(d.status), tone: toStatusTone(d.status)),
              ],
            ),
            const SizedBox(height: HrisSpace.s1),
            Text(d.purpose, style: TextStyle(fontSize: HrisType.md, fontWeight: HrisType.semibold, color: t.text)),
            const SizedBox(height: 2),
            Text(
              '${d.dateFrom == d.dateTo ? ManilaTime.dateOnly(d.dateFrom) : '${ManilaTime.dateOnly(d.dateFrom)} – ${ManilaTime.dateOnly(d.dateTo)}'}'
              ' · ${toDayTypes[d.dayType] ?? d.dayType}',
              style: meta,
            ),
            const SizedBox(height: HrisSpace.s3),
            if (_error != null) ...[
              MessageBanner.error(_error!, onClose: () => setState(() => _error = null)),
              const SizedBox(height: HrisSpace.s3),
            ],
            if (_ok != null) ...[
              MessageBanner.success(_ok!, onClose: () => setState(() => _ok = null)),
              const SizedBox(height: HrisSpace.s3),
            ],
            if (d.status == 'pending') ...[
              const Note("Waiting for approval. You can check in and upload proof once it's approved."),
              const SizedBox(height: HrisSpace.s3),
              OutlinedButton(onPressed: _busy ? null : () => _cancel(d), child: const Text('Cancel this Travel Order')),
              const SizedBox(height: HrisSpace.s4),
            ],
            if (d.completedBy != null) ...[
              Note('Completed by ${d.completedBy}.'),
              const SizedBox(height: HrisSpace.s3),
            ],

            for (var i = 0; i < d.stops.length; i++) ...[
              _StopCard(
                index: i,
                stop: d.stops[i],
                photos: d.photosFor(d.stops[i].id),
                baseUrl: widget.baseUrl,
                isNext: d.stops[i].id == d.nextDestId,
                approved: approved,
                locked: locked,
                busy: _busy,
                onCheckIn: () => _checkIn(d.stops[i]),
                onAddPhotos: () => _addPhotos(d.stops[i]),
              ),
              const SizedBox(height: HrisSpace.s3),
            ],

            if (approved) ...[
              const SizedBox(height: HrisSpace.s2),
              TextField(
                controller: _remarks,
                enabled: !_busy && !locked,
                minLines: 2,
                maxLines: 5,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Completion remarks',
                  helperText: 'Describe your trip.',
                  alignLabelWithHint: true,
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (locked)
                const Note('Remarks submitted — your trip is locked pending approval. Contact an administrator to make changes.')
              else ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: _busy || _remarks.text.trim().isEmpty || _remarks.text.trim() == d.completionRemarks.trim()
                        ? null
                        : _saveRemarks,
                    child: const Text('Save remarks'),
                  ),
                ),
                const SizedBox(height: HrisSpace.s2),
                const Note(
                    'Once every stop is checked in, has $toMinPhotos photos, and your remarks are saved, an approver can mark this completed. '
                    'Saving the remarks locks your trip.'),
              ],
              const SizedBox(height: HrisSpace.s4),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Completion checklist',
                        style: TextStyle(fontSize: HrisType.sm, fontWeight: HrisType.semibold, color: t.text)),
                    const SizedBox(height: HrisSpace.s2),
                    if (d.completionReady)
                      Text('All set — your approver can mark this completed.', style: TextStyle(fontSize: HrisType.sm, color: t.success.text))
                    else
                      for (final r in d.completionReasons)
                        Padding(
                          padding: const EdgeInsets.only(bottom: HrisSpace.s1),
                          child: Text('• $r', style: meta),
                        ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Travel Order')),
      body: SafeArea(child: body),
    );
  }
}

class _StopCard extends StatelessWidget {
  final int index;
  final TravelStop stop;
  final List<TravelPhoto> photos;
  final String baseUrl;
  final bool isNext;
  final bool approved;
  final bool locked;
  final bool busy;
  final VoidCallback onCheckIn;
  final VoidCallback onAddPhotos;

  const _StopCard({
    required this.index,
    required this.stop,
    required this.photos,
    required this.baseUrl,
    required this.isNext,
    required this.approved,
    required this.locked,
    required this.busy,
    required this.onCheckIn,
    required this.onAddPhotos,
  });

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final arrivedText = stop.arrived
        ? 'Checked in${stop.arrivedAt != null ? ' ${ManilaTime.dateTime(stop.arrivedAt!)}' : ''}'
        : 'Not yet checked in';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: stop.arrived ? t.success.bg : t.neutral.bg,
                  border: Border.all(color: stop.arrived ? t.success.border : t.border),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text('${index + 1}',
                    style: TextStyle(fontSize: HrisType.sm, fontWeight: HrisType.semibold, color: stop.arrived ? t.success.text : t.text2)),
              ),
              const SizedBox(width: HrisSpace.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(stop.name, style: TextStyle(fontSize: HrisType.md, fontWeight: HrisType.medium, color: t.text)),
                    const SizedBox(height: 2),
                    Text('$arrivedText · ${photos.length}/$toMinPhotos photos',
                        style: TextStyle(fontSize: HrisType.xs, height: 18 / 12, color: t.text2)),
                  ],
                ),
              ),
            ],
          ),
          if (photos.isNotEmpty) ...[
            const SizedBox(height: HrisSpace.s3),
            Wrap(
              spacing: HrisSpace.s2,
              runSpacing: HrisSpace.s2,
              children: [
                for (final p in photos)
                  GestureDetector(
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (ctx) => Dialog(
                        child: InteractiveViewer(child: Image.network('$baseUrl${p.fileUrl}', fit: BoxFit.contain)),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(HrisRadius.control),
                      child: Image.network(
                        '$baseUrl${p.fileUrl}',
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        semanticLabel: 'Proof photo for ${stop.name}',
                        errorBuilder: (_, _, _) => Container(
                          width: 72,
                          height: 72,
                          color: t.neutral.bg,
                          child: Icon(Icons.image_outlined, color: t.muted),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (approved) ...[
            const SizedBox(height: HrisSpace.s3),
            if (!stop.arrived && isNext)
              FilledButton.icon(
                onPressed: busy ? null : onCheckIn,
                icon: const Icon(Icons.place_outlined),
                label: const Text('Check in here'),
              )
            else if (!stop.arrived)
              const Note('Check in to the earlier stops first.')
            else if (!locked)
              OutlinedButton.icon(
                onPressed: busy ? null : onAddPhotos,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Add photos'),
              ),
          ],
        ],
      ),
    );
  }
}
