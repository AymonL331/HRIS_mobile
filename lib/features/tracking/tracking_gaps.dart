import 'package:flutter/material.dart';

import '../../core/auth/session_controller.dart';
import '../../core/device/device_readiness_service.dart';
import '../../core/http/endpoints.dart';
import '../../core/location/location_gate_service.dart';
import '../../core/time/manila_time.dart';
import 'tracking_service.dart';

/// LONG GAPS NEED A REASON (migration 119, user 2026-11-13). Before clock-out the
/// app asks the server for the open shift's gaps over 30 minutes that have no
/// reason yet; the employee writes one per gap; HR sees it beside the gap on the
/// website's Location Tracking page.

class TrackingGap {
  final DateTime startAt;
  final DateTime endAt;
  final int minutes;

  const TrackingGap({required this.startAt, required this.endAt, required this.minutes});

  factory TrackingGap.fromJson(Map<String, dynamic> j) => TrackingGap(
        startAt: DateTime.parse(j['start_at'] as String).toUtc(),
        endAt: DateTime.parse(j['end_at'] as String).toUtc(),
        minutes: (j['minutes'] as num).toInt(),
      );
}

abstract class TrackingGapsApi {
  Future<List<TrackingGap>> needingReason(int attendanceLogId);

  Future<void> submit(int attendanceLogId, Map<TrackingGap, String> reasons);
}

class MobileTrackingGapsApi implements TrackingGapsApi {
  final SessionController session;

  const MobileTrackingGapsApi(this.session);

  @override
  Future<List<TrackingGap>> needingReason(int attendanceLogId) => session.guard(() => session.client.get(
        Endpoints.trackingGaps,
        query: {'attendance_log_id': '$attendanceLogId'},
        parse: (d) => ((d as Map<String, dynamic>)['gaps'] as List)
            .map((g) => TrackingGap.fromJson((g as Map).cast<String, dynamic>()))
            .toList(),
      ));

  @override
  Future<void> submit(int attendanceLogId, Map<TrackingGap, String> reasons) =>
      session.guard(() => session.client.post(
            Endpoints.trackingGapReasons,
            body: {
              'attendance_log_id': attendanceLogId,
              'reasons': [
                for (final e in reasons.entries)
                  {
                    'start_at': e.key.startAt.toIso8601String(),
                    'end_at': e.key.endAt.toIso8601String(),
                    'reason': e.value,
                  },
              ],
            },
          ));
}

/// Runs before a clock-out. True = go on with the clock-out; false = the
/// employee cancelled. A server or network problem never blocks a clock-out —
/// the gaps still show on the website, just without a reason.
Future<bool> explainGapsBeforeClockOut(
  BuildContext context, {
  required int attendanceLogId,
  required TrackingGapsApi api,
  TrackingService? tracking,
}) async {
  // Send what the phone still holds first, so a gap that is only waiting to
  // upload is not asked about.
  await tracking?.flushNow();
  final List<TrackingGap> gaps;
  try {
    gaps = await api.needingReason(attendanceLogId);
  } catch (_) {
    return true;
  }
  if (gaps.isEmpty || !context.mounted) return true;
  final reasons = await showDialog<Map<TrackingGap, String>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => GapReasonsDialog(gaps: gaps),
  );
  if (reasons == null) return false;
  try {
    await api.submit(attendanceLogId, reasons);
  } catch (_) {
    // Saved or not, the clock-out goes on; the website still shows the gap.
  }
  return true;
}

class GapReasonsDialog extends StatefulWidget {
  final List<TrackingGap> gaps;

  const GapReasonsDialog({super.key, required this.gaps});

  @override
  State<GapReasonsDialog> createState() => _GapReasonsDialogState();
}

class _GapReasonsDialogState extends State<GapReasonsDialog> {
  late final List<TextEditingController> _fields = [for (final _ in widget.gaps) TextEditingController()];

  @override
  void dispose() {
    for (final f in _fields) {
      f.dispose();
    }
    super.dispose();
  }

  bool get _complete => _fields.every((f) => f.text.trim().length >= 3);

  String _length(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '$m min';
    return m == 0 ? '$h h' : '$h h $m min';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Explain the time with no location'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ATLAS has no record of where you were during these times. '
              'Tell HR what happened (for example: phone battery died, no signal inside a building).',
            ),
            for (var i = 0; i < widget.gaps.length; i++) ...[
              const SizedBox(height: 16),
              Text(
                '${ManilaTime.time(widget.gaps[i].startAt)} – ${ManilaTime.time(widget.gaps[i].endAt)}'
                ' (${_length(widget.gaps[i].minutes)})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _fields[i],
                maxLength: 500,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'What happened?', border: OutlineInputBorder()),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _complete
              ? () => Navigator.of(context).pop({
                    for (var i = 0; i < widget.gaps.length; i++) widget.gaps[i]: _fields[i].text.trim(),
                  })
              : null,
          child: const Text('Send and clock out'),
        ),
      ],
    );
  }
}

/// THE CLOCK-IN CHECK (step 2, 2026-11-13): everything recording needs, read
/// again at every clock-in. Null = ready; otherwise what to fix, in plain words.
Future<String?> trackingReadinessProblem({
  required LocationGateService gate,
  required DeviceReadinessService device,
}) async {
  final GateVerdict verdict;
  final DeviceReadiness d;
  try {
    verdict = await gate.check();
    d = await device.check();
  } catch (_) {
    return null; // unreadable: never block a clock-in on a check that failed
  }
  switch (verdict) {
    case GateVerdict.serviceOff:
      return 'Location is turned off. Turn it on, then clock in.';
    case GateVerdict.permissionDenied:
    case GateVerdict.permissionDeniedForever:
      return 'ATLAS is not allowed to use your location. Allow it, then clock in.';
    case GateVerdict.backgroundDenied:
      return 'Location must be set to "Allow all the time" so your shift is recorded.';
    case GateVerdict.reducedAccuracy:
      return 'Turn on "Use precise location" for ATLAS, then clock in.';
    case GateVerdict.ok:
      break;
  }
  if (!d.notificationsGranted) return 'Allow ATLAS notifications so it can tell you when recording stops.';
  if (!d.batteryUnrestricted) {
    return 'Set ATLAS battery use to "Unrestricted" (no battery saving) so your phone does not close it during your shift.';
  }
  return null;
}
