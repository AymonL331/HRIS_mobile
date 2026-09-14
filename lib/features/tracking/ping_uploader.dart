import '../../core/http/api_exception.dart';
import 'ping_queue.dart';

/// Sends one batch body to `POST /api/me/tracking/pings` and returns its `data`.
typedef PingPoster = Future<Map<String, dynamic>> Function(Map<String, dynamic> body);

/// Why recording must end, as learned from an upload.
enum UploadStop {
  none,

  /// 401 / mobile access switched off / account inactive: this phone is signed
  /// out. The queue is KEPT — the points are real and may still be sent later.
  sessionEnded,

  /// The app's location consent is no longer on record: nothing further may be
  /// stored, so the queue is CLEARED (RA 10173).
  consentWithdrawn,
}

class UploadResult {
  final int sent;
  final int accepted;
  final int rejected;

  /// Removed from the queue without being stored (the shift is gone, or the
  /// batch was malformed) — never retried, so it can never jam the queue.
  final int dropped;

  /// Per shift, what the server said about recording: `false` = that shift is
  /// closed. Keyed by shift because an old shift's leftovers can share a flush
  /// with today's points, and "yesterday is closed" must not stop today.
  final Map<int, bool> activeByShift;

  final UploadStop stop;

  /// A transient failure (no network, server down): try again later, keep all.
  final bool retryLater;

  const UploadResult({
    this.sent = 0,
    this.accepted = 0,
    this.rejected = 0,
    this.dropped = 0,
    this.activeByShift = const {},
    this.stop = UploadStop.none,
    this.retryLater = false,
  });
}

/// Drains the offline queue to the server, oldest first, one shift per batch.
///
/// Pure policy over an injected poster, so every failure path is unit-tested
/// without a network: what is kept, what is retried, what is dropped, and what
/// ends recording.
class PingUploader {
  final PingQueue queue;
  final PingPoster post;
  final DateTime Function() nowUtc;
  final int batchSize;

  PingUploader({
    required this.queue,
    required this.post,
    DateTime Function()? nowUtc,
    this.batchSize = 100,
  }) : nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  Future<UploadResult> flush({int maxBatches = 20}) async {
    var sent = 0;
    var accepted = 0;
    var rejected = 0;
    var dropped = 0;
    final active = <int, bool>{};

    UploadResult result({UploadStop stop = UploadStop.none, bool retryLater = false}) => UploadResult(
          sent: sent,
          accepted: accepted,
          rejected: rejected,
          dropped: dropped,
          activeByShift: active,
          stop: stop,
          retryLater: retryLater,
        );

    for (var i = 0; i < maxBatches; i++) {
      final head = await queue.oldest(limit: batchSize);
      if (head.isEmpty) break;
      final shift = head.first.attendanceLogId;
      final batch = head.where((p) => p.attendanceLogId == shift).toList(growable: false);
      final uuids = batch.map((p) => p.uuid).toList(growable: false);
      final body = {
        'attendance_log_id': shift,
        // The server corrects every point by (server now − this), so a phone
        // whose clock is minutes off still lands its points in the right place.
        'device_now': nowUtc().toIso8601String(),
        'pings': [for (final p in batch) p.toJson()],
      };

      try {
        final data = await post(body);
        // Deleted only now, after the server acknowledged the batch.
        await queue.remove(uuids);
        sent += batch.length;
        accepted += _int(data['accepted']);
        rejected += _int(data['rejected']);
        active[shift] = data['tracking_active'] == true;
      } on ApiException catch (e) {
        if (e.isNetwork || e.status >= 500 || e.status == 429 || e.code == 'INVALID_ENVELOPE' || e.passwordChangeRequired) {
          return result(retryLater: true);
        }
        if (e.endsSession || e.code == 'MOBILE_ONLY') {
          return result(stop: UploadStop.sessionEnded);
        }
        if (e.isValidation && e.fieldErrors.containsKey('location_consent')) {
          await queue.clear();
          return result(stop: UploadStop.consentWithdrawn);
        }
        if (e.status == 404) {
          // The shift no longer exists (deleted by HR): its points can never land.
          final n = batch.length;
          await queue.removeShift(shift);
          dropped += n;
          active[shift] = false;
          continue;
        }
        if (e.isValidation) {
          // A malformed envelope. Retrying would fail identically forever and
          // block every point queued behind it, so this batch is let go.
          await queue.remove(uuids);
          dropped += batch.length;
          continue;
        }
        return result(retryLater: true);
      }
    }
    return result();
  }

  static int _int(Object? v) => v is int ? v : int.tryParse('$v') ?? 0;
}
