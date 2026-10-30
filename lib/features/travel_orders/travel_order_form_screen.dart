import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/http/api_exception.dart';
import '../../core/location/location_fix.dart';
import '../../core/time/manila_time.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/message_banner.dart';
import '../attendance/correction_form_screen.dart' show PickedProof, ProofPicker, ProofCameraDenied, pickProofPhoto;
import 'travel_order_api.dart';
import 'travel_order_models.dart';

const _maxMb = 5;

/// A stop being typed: its name and, once pinned, its coordinates as text (the
/// web form lets HR type them too).
class _StopDraft {
  final name = TextEditingController();
  final lat = TextEditingController();
  final lng = TextEditingController();

  void dispose() {
    name.dispose();
    lat.dispose();
    lng.dispose();
  }

  bool get blank => name.text.trim().isEmpty && lat.text.trim().isEmpty && lng.text.trim().isEmpty;
}

/// FILE A TRAVEL ORDER (2026-10-29) — the web's TravelOrderFormDialog (self mode)
/// on the phone, with the same body and rules: purpose, from/to dates, day type,
/// each stop pinned (Use my location, or typed coordinates), and the approved
/// travel authority image — staged first, then the order is filed with its URL.
/// The server re-checks everything (incl. the approved face). Pops `true` once filed.
class TravelOrderFormScreen extends StatefulWidget {
  final TravelOrderApi api;
  final LocationFixService fixes;
  final ProofPicker picker;

  const TravelOrderFormScreen({super.key, required this.api, required this.fixes, this.picker = pickProofPhoto});

  static Future<bool?> open(BuildContext context,
          {required TravelOrderApi api, required LocationFixService fixes, ProofPicker picker = pickProofPhoto}) =>
      Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => TravelOrderFormScreen(api: api, fixes: fixes, picker: picker)),
      );

  @override
  State<TravelOrderFormScreen> createState() => _TravelOrderFormScreenState();
}

class _TravelOrderFormScreenState extends State<TravelOrderFormScreen> {
  final _purpose = TextEditingController();
  final _stops = <_StopDraft>[_StopDraft()];
  String? _from;
  String? _to;
  String _dayType = 'whole_day';
  PickedProof? _authority;
  Map<String, String> _errors = {};
  String? _formError;
  bool _busy = false;
  int _locating = -1;

  @override
  void dispose() {
    _purpose.dispose();
    for (final s in _stops) {
      s.dispose();
    }
    super.dispose();
  }

  String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate(bool from) async {
    final now = DateTime.now();
    final current = DateTime.tryParse((from ? _from : _to) ?? _from ?? '') ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(now.year - 1, 1, 1),
      lastDate: DateTime(now.year + 2, 12, 31),
      helpText: from ? 'Trip starts' : 'Trip ends',
    );
    if (picked == null) return;
    setState(() {
      if (from) {
        _from = _ymd(picked);
        // A one-day trip is the usual case: the end follows the start until set.
        if (_to == null || _to!.compareTo(_from!) < 0) _to = _from;
      } else {
        _to = _ymd(picked);
      }
      _errors = {..._errors}
        ..remove('date_from')
        ..remove('date_to');
    });
  }

  Future<void> _useMyLocation(int i) async {
    setState(() => _locating = i);
    try {
      final fix = await widget.fixes.acquire();
      if (!mounted) return;
      final check = validateFix(fix);
      if (check is FixMocked) {
        setState(() => _errors = {..._errors, 'stop$i': 'Your phone reported a mock location. Turn it off and try again.'});
        return;
      }
      setState(() {
        _stops[i].lat.text = fix.latitude.toStringAsFixed(7);
        _stops[i].lng.text = fix.longitude.toStringAsFixed(7);
        _errors = {..._errors}..remove('stop$i');
      });
    } on FixTimeout {
      if (mounted) setState(() => _errors = {..._errors, 'stop$i': 'Could not read your location — try again, or type the coordinates.'});
    } catch (_) {
      if (mounted) setState(() => _errors = {..._errors, 'stop$i': 'Could not read your location — check that location is on.'});
    } finally {
      if (mounted) setState(() => _locating = -1);
    }
  }

  Future<void> _chooseAuthority() async {
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
              subtitle: const Text('A photo or scan of the approved travel authority'),
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
          _errors = {..._errors, 'file': problem};
        } else {
          _authority = picked;
          _errors = {..._errors}..remove('file');
        }
      });
    } on ProofCameraDenied {
      if (mounted) {
        setState(() => _errors = {..._errors, 'file': 'Camera permission is off. Allow it in Settings, or choose from the gallery.'});
      }
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final purpose = _purpose.text.trim();
    final local = <String, String>{};
    if (purpose.isEmpty) local['purpose'] = 'Enter the purpose.';
    if (_from == null) local['date_from'] = 'Select a start date.';
    if (_to == null) local['date_to'] = 'Select an end date.';
    if (_from != null && _to != null && _from!.compareTo(_to!) > 0) local['date_to'] = 'End date cannot be before the start date.';
    final stops = <Map<String, dynamic>>[];
    for (var i = 0; i < _stops.length; i++) {
      final s = _stops[i];
      if (s.blank) continue;
      final lat = double.tryParse(s.lat.text.trim());
      final lng = double.tryParse(s.lng.text.trim());
      if (s.name.text.trim().isEmpty) {
        local['stop$i'] = 'Enter the place name.';
      } else if (lat == null || lng == null) {
        local['stop$i'] = 'Pin the location — tap Use my location, or type the coordinates.';
      } else {
        stops.add({'name': s.name.text.trim(), 'lat': lat, 'lng': lng});
      }
    }
    if (stops.isEmpty && !local.keys.any((k) => k.startsWith('stop'))) local['destinations'] = 'Add at least one destination.';
    if (_authority == null) local['file'] = 'Attach the approved travel authority (image).';
    setState(() {
      _errors = local;
      _formError = null;
    });
    if (local.isNotEmpty) return;

    setState(() => _busy = true);
    try {
      // 1) Stage the authority image; the order is filed only once that succeeds.
      final url = await widget.api.stageAttachment(bytes: _authority!.bytes, mimeType: _authority!.mimeType, name: _authority!.name);
      if (url.isEmpty) throw const ApiException(status: 0, message: 'The travel authority could not be uploaded. Please try again.');
      // 2) File it. employee_id is forced to me on the server.
      await widget.api.create({
        'purpose': purpose,
        'date_from': _from,
        'date_to': _to,
        'day_type': _dayType,
        'attachment_url': url,
        'destinations': stops,
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        final f = e.fieldErrors;
        final mapped = <String, String>{
          for (final k in const ['purpose', 'date_from', 'date_to', 'day_type', 'destinations'])
            if (f[k] != null) k: f[k]!,
          if ((f['attachment_url'] ?? f['type'] ?? f['data'] ?? f['file']) != null)
            'file': (f['attachment_url'] ?? f['type'] ?? f['data'] ?? f['file'])!,
        };
        // "destinations[0].lat" → that stop's line.
        for (final entry in f.entries) {
          final m = RegExp(r'^destinations\[(\d+)\]').firstMatch(entry.key);
          if (m != null) mapped['stop${m.group(1)}'] = entry.value;
        }
        _errors = mapped;
        // The face rule, a destination message, anything not tied to one field.
        if (mapped.isEmpty || !mapped.keys.any((k) => !k.startsWith('stop'))) _formError = e.message;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final hintStyle = TextStyle(fontSize: HrisType.xs, height: 18 / 12, color: t.text2);
    final errorStyle = TextStyle(fontSize: HrisType.xs, height: 18 / 12, color: t.danger.text);

    Widget requiredLabel(String text) => Text.rich(TextSpan(text: text, children: [
          TextSpan(text: ' *', style: TextStyle(color: t.danger.solid)),
        ]));

    Widget dateField(String label, String? value, VoidCallback onTap, String? error) => InkWell(
          onTap: _busy ? null : onTap,
          borderRadius: BorderRadius.circular(HrisRadius.control),
          child: InputDecorator(
            isEmpty: value == null,
            decoration: InputDecoration(
              label: requiredLabel(label),
              errorText: error,
              errorMaxLines: 2,
              floatingLabelBehavior: FloatingLabelBehavior.always,
              suffixIcon: const Icon(Icons.calendar_today_outlined),
            ),
            child: Text(value == null ? 'Select a date' : ManilaTime.dateOnly(value),
                style: TextStyle(fontSize: HrisType.md, color: value == null ? t.muted : t.text)),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('File a Travel Order')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s4, HrisSpace.s4, HrisSpace.s6),
          children: [
            Text(
              "Pin each stop you'll visit. Your request is submitted for approval; you'll collect proof after it's approved.",
              style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text2),
            ),
            const SizedBox(height: HrisSpace.s4),
            if (_formError != null) ...[
              MessageBanner.error(_formError!),
              const SizedBox(height: HrisSpace.s3),
            ],
            TextField(
              controller: _purpose,
              enabled: !_busy,
              maxLength: 255,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                label: requiredLabel('Purpose'),
                floatingLabelBehavior: FloatingLabelBehavior.always,
                hintText: 'e.g. Branch visit',
                errorText: _errors['purpose'],
              ),
              onChanged: (_) {
                if (_errors.containsKey('purpose')) setState(() => _errors = {..._errors}..remove('purpose'));
              },
            ),
            const SizedBox(height: HrisSpace.s3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: dateField('From', _from, () => _pickDate(true), _errors['date_from'])),
                const SizedBox(width: HrisSpace.s3),
                Expanded(child: dateField('To', _to, () => _pickDate(false), _errors['date_to'])),
              ],
            ),
            const SizedBox(height: HrisSpace.s4),
            DropdownButtonFormField<String>(
              initialValue: _dayType,
              decoration: const InputDecoration(labelText: 'Day type', floatingLabelBehavior: FloatingLabelBehavior.always),
              items: [for (final e in toDayTypes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: _busy ? null : (v) => setState(() => _dayType = v ?? 'whole_day'),
            ),
            const SizedBox(height: HrisSpace.s5),

            Text('Destinations', style: TextStyle(fontSize: HrisType.sm, fontWeight: HrisType.medium, color: t.text)),
            const SizedBox(height: HrisSpace.s1),
            Text('Check-ins on the trip follow this order.', style: hintStyle),
            for (var i = 0; i < _stops.length; i++) ...[
              const SizedBox(height: HrisSpace.s3),
              Container(
                padding: const EdgeInsets.all(HrisSpace.s3),
                decoration: BoxDecoration(
                  color: t.surface,
                  border: Border.all(color: _errors['stop$i'] != null ? t.danger.border : t.border),
                  borderRadius: BorderRadius.circular(HrisRadius.panel),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('Stop ${i + 1}',
                              style: TextStyle(fontSize: HrisType.sm, fontWeight: HrisType.semibold, color: t.text)),
                        ),
                        if (_stops.length > 1)
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                      _stops.removeAt(i).dispose();
                                      _errors = {};
                                    }),
                            child: const Text('Remove'),
                          ),
                      ],
                    ),
                    TextField(
                      controller: _stops[i].name,
                      enabled: !_busy,
                      maxLength: 160,
                      decoration: const InputDecoration(labelText: 'Place name', hintText: 'e.g. Daraga Branch', counterText: ''),
                    ),
                    const SizedBox(height: HrisSpace.s2),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _stops[i].lat,
                            enabled: !_busy,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                            decoration: const InputDecoration(labelText: 'Latitude'),
                          ),
                        ),
                        const SizedBox(width: HrisSpace.s2),
                        Expanded(
                          child: TextField(
                            controller: _stops[i].lng,
                            enabled: !_busy,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                            decoration: const InputDecoration(labelText: 'Longitude'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: HrisSpace.s2),
                    OutlinedButton.icon(
                      onPressed: _busy || _locating >= 0 ? null : () => _useMyLocation(i),
                      icon: _locating == i
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.my_location),
                      label: const Text('Use my location'),
                    ),
                    if (_errors['stop$i'] != null) ...[
                      const SizedBox(height: HrisSpace.s1),
                      Text(_errors['stop$i']!, style: errorStyle),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: HrisSpace.s2),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy ? null : () => setState(() => _stops.add(_StopDraft())),
                icon: const Icon(Icons.add),
                label: const Text('Add destination'),
              ),
            ),
            if (_errors['destinations'] != null) Text(_errors['destinations']!, style: errorStyle),
            const SizedBox(height: HrisSpace.s4),

            Text.rich(
              TextSpan(text: 'Approved travel authority (image)', children: [
                TextSpan(text: ' *', style: TextStyle(color: t.danger.solid)),
              ]),
              style: TextStyle(fontSize: HrisType.sm, fontWeight: HrisType.medium, color: t.text),
            ),
            const SizedBox(height: HrisSpace.s1),
            Text('JPEG, PNG, WEBP, or GIF, up to $_maxMb MB.', style: hintStyle),
            const SizedBox(height: HrisSpace.s2),
            if (_authority != null)
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
                          _authority!.bytes,
                          fit: BoxFit.contain,
                          semanticLabel: 'The selected travel authority',
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
                        Expanded(child: Text(_authority!.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: hintStyle)),
                        OutlinedButton(onPressed: _busy ? null : () => setState(() => _authority = null), child: const Text('Remove')),
                      ],
                    ),
                  ],
                ),
              )
            else
              OutlinedButton(onPressed: _busy ? null : _chooseAuthority, child: const Text('Choose image')),
            if (_errors['file'] != null) ...[
              const SizedBox(height: HrisSpace.s1),
              Text(_errors['file']!, style: errorStyle),
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
                      : const Text('Submit request'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
