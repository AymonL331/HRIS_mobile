import 'package:flutter/material.dart';

import '../../core/time/manila_time.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/app_card.dart';
import 'tracking_models.dart';
import 'tracking_service.dart';

/// Tells the employee, plainly, whether their work location is being recorded
/// right now — the in-app twin of the service's notification.
///
/// Shown only while the SERVER says the shift is open. When the shift is open
/// but this phone is not recording (the service was refused, or killed and not
/// yet back), it says so and offers a restart, rather than letting the employee
/// believe a trail exists that does not.
class TrackingStatusCard extends StatelessWidget {
  final TrackingState state;
  final TrackingSnapshot snapshot;
  final VoidCallback onRestart;
  final DateTime nowUtc;

  const TrackingStatusCard({
    super.key,
    required this.state,
    required this.snapshot,
    required this.onRestart,
    required this.nowUtc,
  });

  @override
  Widget build(BuildContext context) {
    if (!state.active) return const SizedBox.shrink();
    final t = HrisTokens.of(context);
    final recording = snapshot.running && snapshot.attendanceLogId == state.attendanceLogId;
    final set = recording ? (snapshot.uploadFailing ? t.warning : t.success) : t.warning;

    final String title;
    final List<String> lines;
    if (recording) {
      title = 'Recording your work location';
      final last = snapshot.lastPointAt;
      lines = [
        [
          if (state.since != null) 'Since ${ManilaTime.time(state.since!)}',
          last == null ? 'waiting for GPS' : 'last point ${_ago(last)}',
          if (snapshot.queued > 0) '${snapshot.queued} waiting to upload',
        ].join(' · '),
        if (snapshot.uploadFailing) 'Cannot reach the server — your points are saved on this phone and upload when you are back online.',
        'Recording stops when you clock out.',
      ];
    } else {
      title = 'Location recording is not running';
      lines = [
        'Your shift is open but this phone is not recording where you are.',
        if (snapshot.stopReason == 'could_not_start')
          'Android refused to start it. Check that location is set to "Allow all the time", then tap Restart.'
        else
          'Tap Restart. If it keeps stopping, open the app settings and allow HRIS to run in the background.',
      ];
    }

    return AppCard(
      padding: const EdgeInsets.all(HrisSpace.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(recording ? Icons.share_location : Icons.location_disabled_outlined, color: set.text),
          const SizedBox(width: HrisSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: HrisType.md, fontWeight: HrisType.semibold, height: 1.35, color: set.text)),
                const SizedBox(height: HrisSpace.s1),
                for (final l in lines)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(l, style: TextStyle(fontSize: HrisType.xs, height: 1.45, color: t.muted)),
                  ),
                if (!recording) ...[
                  const SizedBox(height: HrisSpace.s2),
                  OutlinedButton.icon(onPressed: onRestart, icon: const Icon(Icons.refresh), label: const Text('Restart')),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _ago(DateTime at) {
    final s = nowUtc.difference(at.toUtc()).inSeconds;
    if (s < 60) return 'just now';
    if (s < 3600) return '${s ~/ 60} min ago';
    return 'at ${ManilaTime.time(at)}';
  }
}
