import 'package:flutter/material.dart';

import '../../core/http/api_exception.dart';
import '../../core/location/location_fix.dart';
import '../../core/time/manila_time.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/kit.dart';
import '../../shared/widgets/message_banner.dart';
import '../../shared/widgets/status_badge.dart';
import '../attendance/correction_form_screen.dart' show ProofPicker, pickProofPhoto;
import 'travel_order_api.dart';
import 'travel_order_detail_screen.dart';
import 'travel_order_form_screen.dart';
import 'travel_order_models.dart';

/// MY TRAVEL ORDERS (2026-10-29) — the web My Travel Orders on the phone: file a
/// trip, track approval, then open it to check in at each stop, add the proof
/// photos and the completion remarks. Same server calls, same rules: filing
/// needs an approved face (the checklist shows the steps until then).
class TravelOrdersScreen extends StatefulWidget {
  final TravelOrderApi api;
  final LocationFixService fixes;
  final String baseUrl;
  final ProofPicker picker;
  final VoidCallback? onOpenTimeClock;
  final VoidCallback? onOpenProfilePhoto;

  /// Whether this page is the one showing. The shell keeps every page built, so
  /// the list loads when the page is opened (and again each time), not at start.
  final bool active;

  const TravelOrdersScreen({
    super.key,
    required this.api,
    required this.fixes,
    required this.baseUrl,
    this.picker = pickProofPhoto,
    this.onOpenTimeClock,
    this.onOpenProfilePhoto,
    this.active = true,
  });

  @override
  State<TravelOrdersScreen> createState() => _TravelOrdersScreenState();
}

class _TravelOrdersScreenState extends State<TravelOrdersScreen> {
  List<TravelOrderSummary>? _items;
  TravelReadiness? _readiness;
  String? _error;
  // False until the page is first opened: a hidden page must not spin.
  bool _loading = false;
  String? _flash;

  @override
  void initState() {
    super.initState();
    if (widget.active) _load();
  }

  @override
  void didUpdateWidget(TravelOrdersScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([widget.api.list(), widget.api.readiness()]);
      if (!mounted) return;
      setState(() {
        _items = results[0] as List<TravelOrderSummary>;
        _readiness = results[1] as TravelReadiness;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _file() async {
    final filed = await TravelOrderFormScreen.open(context, api: widget.api, fixes: widget.fixes, picker: widget.picker);
    if (filed == true && mounted) {
      setState(() => _flash = 'Travel Order filed — pending approval.');
      await _load();
    }
  }

  Future<void> _open(TravelOrderSummary o) async {
    await TravelOrderDetailScreen.open(
      context,
      api: widget.api,
      id: o.id,
      fixes: widget.fixes,
      baseUrl: widget.baseUrl,
      picker: widget.picker,
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final items = _items;
    final canFile = _readiness?.ready ?? false;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s2, HrisSpace.s4, HrisSpace.s6),
        children: [
          Text(
            'File a trip, track approval, check in, and upload proof.',
            style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text2),
          ),
          const SizedBox(height: HrisSpace.s3),
          if (_flash != null) ...[
            MessageBanner.success(_flash!, onClose: () => setState(() => _flash = null)),
            const SizedBox(height: HrisSpace.s3),
          ],
          if (canFile)
            FilledButton.icon(
              onPressed: _file,
              icon: const Icon(Icons.add),
              label: const Text('File a Travel Order'),
            ),
          if (!_loading && _readiness != null && !canFile)
            _ReadinessCard(
              readiness: _readiness!,
              onOpenTimeClock: widget.onOpenTimeClock,
              onOpenProfilePhoto: widget.onOpenProfilePhoto,
            ),
          const SizedBox(height: HrisSpace.s4),
          if (_loading && items == null)
            const LoadingBlock(semanticsLabel: 'Loading travel orders')
          else if (_error != null && items == null)
            StatePanel(
              title: "Couldn't load your travel orders",
              message: _error,
              error: true,
              action: OutlinedButton(onPressed: _load, child: const Text('Try again')),
            )
          else if (items != null && items.isEmpty)
            StatePanel(
              title: 'No travel orders yet',
              message: canFile ? 'Use File a Travel Order above — your trips will appear here.' : null,
            )
          else if (items != null)
            RuledList(
              children: [
                for (final o in items)
                  RuledRow(
                    onTap: () => _open(o),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(o.toNumber,
                                  style: TextStyle(fontFamily: HrisFont.mono, fontSize: HrisType.xs, color: t.text2)),
                              const SizedBox(height: 2),
                              Text(o.purpose,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: HrisType.md, fontWeight: HrisType.medium, color: t.text)),
                              const SizedBox(height: 2),
                              Text(
                                o.dateFrom == o.dateTo
                                    ? ManilaTime.dateOnly(o.dateFrom)
                                    : '${ManilaTime.dateOnly(o.dateFrom)} – ${ManilaTime.dateOnly(o.dateTo)}',
                                style: TextStyle(fontSize: HrisType.sm, color: t.text2),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: HrisSpace.s3),
                        StatusBadge(toStatusLabel(o.status), tone: toStatusTone(o.status)),
                        Icon(Icons.chevron_right, color: t.muted),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// "Get ready for Travel Orders": a Travel Order day is clocked by face, so the
/// face must be enrolled and approved before filing. On the phone the face is
/// enrolled from the Time Clock (HR opens it for this phone).
class _ReadinessCard extends StatelessWidget {
  final TravelReadiness readiness;
  final VoidCallback? onOpenTimeClock;
  final VoidCallback? onOpenProfilePhoto;

  const _ReadinessCard({required this.readiness, this.onOpenTimeClock, this.onOpenProfilePhoto});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final r = readiness;
    final photoDone = r.profilePhoto == 'approved';
    final faceWaiting = r.face == 'pending';

    Widget step(int n, String title, String body, {required bool done, bool waiting = false, Widget? action}) => Padding(
          padding: const EdgeInsets.only(top: HrisSpace.s3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                child: Text(done ? '✓' : (waiting ? '⏳' : '$n'),
                    style: TextStyle(fontWeight: HrisType.semibold, color: done ? t.success.text : t.text2)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: HrisType.sm, fontWeight: HrisType.semibold, color: t.text)),
                    const SizedBox(height: 2),
                    Text(body, style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text2)),
                    if (action != null) ...[const SizedBox(height: HrisSpace.s2), action],
                  ],
                ),
              ),
            ],
          ),
        );

    final String faceBody;
    if (r.face == 'enrolled') {
      faceBody = 'Your face is enrolled and approved.';
    } else if (faceWaiting) {
      faceBody = 'Your face was sent — waiting for HR to approve it.';
    } else if (r.face == 'rejected') {
      faceBody = 'HR did not accept your face enrollment${r.faceReason != null ? ': ${r.faceReason}' : ''}. Ask HR to open it again, then enroll from the Time Clock.';
    } else if (!photoDone) {
      faceBody = 'Available once your profile photo is approved.';
    } else {
      faceBody = 'Ask HR to open face enrollment for this phone, then enroll from the Time Clock. It takes about a minute.';
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Get ready for Travel Orders',
              style: TextStyle(fontSize: HrisType.md, fontWeight: HrisType.semibold, color: t.text)),
          const SizedBox(height: HrisSpace.s1),
          Text(
            'A Travel Order day is clocked with your face, so your face must be enrolled and approved before you can file one.',
            style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text2),
          ),
          step(
            1,
            'Profile photo',
            photoDone
                ? 'Your profile photo is on file.'
                : r.profilePhoto == 'pending'
                    ? 'Your photo was sent — waiting for HR to approve it.'
                    : 'HR compares your face enrollment against a photo of you.',
            done: photoDone,
            waiting: r.profilePhoto == 'pending',
            action: !photoDone && r.profilePhoto != 'pending' && onOpenProfilePhoto != null
                ? OutlinedButton(onPressed: onOpenProfilePhoto, child: const Text('Take my profile photo'))
                : null,
          ),
          step(
            2,
            'Face enrollment',
            faceBody,
            done: r.face == 'enrolled',
            waiting: faceWaiting,
            action: photoDone && r.face != 'enrolled' && !faceWaiting && onOpenTimeClock != null
                ? OutlinedButton(onPressed: onOpenTimeClock, child: const Text('Open the Time Clock'))
                : null,
          ),
        ],
      ),
    );
  }
}
