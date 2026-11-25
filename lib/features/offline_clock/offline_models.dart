import 'dart:math' as math;

import '../../core/time/manila_time.dart';

double? _num(Object? v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
int? _int(Object? v) => v == null ? null : (v is int ? v : int.tryParse('$v'));

/// What the phone needs to clock in with NO signal (server migration 132,
/// `GET /api/me/offline-clock/kit`): the employee's OWN enrolled face code(s),
/// the match threshold and the limits. Biometric data: kept only in the
/// keystore-encrypted storage, never logged, never shown.
class OfflineKit {
  final List<List<double>> templates;
  final double threshold;
  final String modelVersion;
  final int maxHours;
  final DateTime fetchedAt;

  const OfflineKit({
    required this.templates,
    required this.threshold,
    required this.modelVersion,
    required this.maxHours,
    required this.fetchedAt,
  });

  bool get usable => templates.isNotEmpty && threshold > 0;

  factory OfflineKit.fromServer(Map<String, dynamic> j, DateTime fetchedAt) => OfflineKit(
        templates: ((j['templates'] as List?) ?? const [])
            .whereType<List>()
            .map((t) => t.map((v) => (v as num).toDouble()).toList(growable: false))
            .toList(growable: false),
        threshold: _num(j['match_threshold']) ?? 0,
        modelVersion: (j['model_version'] ?? '') as String,
        maxHours: _int(j['max_hours']) ?? 48,
        fetchedAt: fetchedAt,
      );

  factory OfflineKit.fromJson(Map<String, dynamic> j) => OfflineKit(
        templates: ((j['templates'] as List?) ?? const [])
            .whereType<List>()
            .map((t) => t.map((v) => (v as num).toDouble()).toList(growable: false))
            .toList(growable: false),
        threshold: _num(j['threshold']) ?? 0,
        modelVersion: (j['model_version'] ?? '') as String,
        maxHours: _int(j['max_hours']) ?? 48,
        fetchedAt: DateTime.tryParse('${j['fetched_at']}')?.toUtc() ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

  Map<String, dynamic> toJson() => {
        'templates': templates,
        'threshold': threshold,
        'model_version': modelVersion,
        'max_hours': maxHours,
        'fetched_at': fetchedAt.toIso8601String(),
      };

  /// The nearest enrolled face, as the server measures it (Euclidean). Null when
  /// no template has the capture's length.
  double? bestDistance(List<double> embedding) {
    double? best;
    for (final t in templates) {
      if (t.length != embedding.length) continue;
      var sum = 0.0;
      for (var i = 0; i < t.length; i++) {
        final d = t[i] - embedding[i];
        sum += d * d;
      }
      final dist = math.sqrt(sum);
      if (best == null || dist < best) best = dist;
    }
    return best;
  }

  @override
  String toString() => 'OfflineKit($modelVersion, ${templates.length} face code(s))';
}

/// The last server time the phone saw, beside the phone's running clock at that
/// moment. "Server time + running time since" is when an offline punch happened,
/// whatever the phone's own clock says — as long as the phone was not restarted.
class TimeAnchor {
  final DateTime serverUtc;
  final int elapsedMs;
  final int? bootCount;

  const TimeAnchor({required this.serverUtc, required this.elapsedMs, required this.bootCount});

  factory TimeAnchor.fromJson(Map<String, dynamic> j) => TimeAnchor(
        serverUtc: DateTime.parse(j['server_utc'] as String).toUtc(),
        elapsedMs: _int(j['elapsed_ms']) ?? 0,
        bootCount: _int(j['boot_count']),
      );

  Map<String, dynamic> toJson() => {
        'server_utc': serverUtc.toIso8601String(),
        'elapsed_ms': elapsedMs,
        'boot_count': bootCount,
      };
}

/// One punch made with no signal, kept on the phone until the server has it.
class OfflinePunch {
  final String clientUuid;
  final String direction; // in | out
  /// The best estimate of WHEN: server time + running time, else the GPS time,
  /// else the phone's clock.
  final DateTime takenAt;
  final DateTime? gpsTime;
  final DateTime? anchorServerAt;
  final int? elapsedSinceAnchorMs;
  final List<double> embedding;
  final List<String> completedChallenges;
  final String modelVersion;
  final double phoneDistance;
  final double latitude;
  final double longitude;
  final double accuracyM;
  final String? photoBase64;
  final String? appVersion;

  /// "Save for HR to check" (2026-11-25): the face did not match on this phone
  /// after 3 tries; [phoneTries] holds each try's score. Always HR review.
  final bool noMatch;
  final List<double> phoneTries;

  const OfflinePunch({
    required this.clientUuid,
    required this.direction,
    required this.takenAt,
    required this.gpsTime,
    required this.anchorServerAt,
    required this.elapsedSinceAnchorMs,
    required this.embedding,
    required this.completedChallenges,
    required this.modelVersion,
    required this.phoneDistance,
    required this.latitude,
    required this.longitude,
    required this.accuracyM,
    required this.photoBase64,
    required this.appVersion,
    this.noMatch = false,
    this.phoneTries = const [],
  });

  /// The Manila day it belongs to.
  String get localDate => ManilaTime.toManila(takenAt).toIso8601String().substring(0, 10);

  /// The body of `POST /api/me/offline-clock`.
  Map<String, dynamic> toRequestJson() => {
        'client_uuid': clientUuid,
        'direction': direction,
        'taken_at': takenAt.toUtc().toIso8601String(),
        if (gpsTime != null) 'gps_time': gpsTime!.toUtc().toIso8601String(),
        if (anchorServerAt != null && elapsedSinceAnchorMs != null)
          'elapsed': {'anchor_server_at': anchorServerAt!.toUtc().toIso8601String(), 'elapsed_ms': elapsedSinceAnchorMs},
        'embedding': embedding,
        'liveness_passed': true,
        'completed_challenges': completedChallenges,
        'model_version': modelVersion,
        'phone_match_distance': phoneDistance,
        'location': {'latitude': latitude, 'longitude': longitude, 'accuracy': accuracyM},
        if (photoBase64 != null && photoBase64!.isNotEmpty) 'photo': {'type': 'image/jpeg', 'data': photoBase64},
        'app_version': ?appVersion,
        if (noMatch) 'phone_no_match': true,
        if (noMatch) 'phone_tries': phoneTries,
      };

  Map<String, dynamic> toJson() => {
        ...toRequestJson(),
        'phone_distance': phoneDistance,
      };

  factory OfflinePunch.fromJson(Map<String, dynamic> j) {
    final el = j['elapsed'] as Map<String, dynamic>?;
    final loc = (j['location'] as Map<String, dynamic>?) ?? const {};
    final photo = j['photo'] as Map<String, dynamic>?;
    return OfflinePunch(
      clientUuid: j['client_uuid'] as String,
      direction: j['direction'] as String,
      takenAt: DateTime.parse(j['taken_at'] as String).toUtc(),
      gpsTime: j['gps_time'] == null ? null : DateTime.parse(j['gps_time'] as String).toUtc(),
      anchorServerAt: el == null ? null : DateTime.parse(el['anchor_server_at'] as String).toUtc(),
      elapsedSinceAnchorMs: el == null ? null : _int(el['elapsed_ms']),
      embedding: ((j['embedding'] as List?) ?? const []).map((v) => (v as num).toDouble()).toList(growable: false),
      completedChallenges: ((j['completed_challenges'] as List?) ?? const []).map((e) => '$e').toList(growable: false),
      modelVersion: (j['model_version'] ?? '') as String,
      phoneDistance: _num(j['phone_distance'] ?? j['phone_match_distance']) ?? 0,
      latitude: _num(loc['latitude']) ?? 0,
      longitude: _num(loc['longitude']) ?? 0,
      accuracyM: _num(loc['accuracy']) ?? 0,
      photoBase64: photo?['data'] as String?,
      appVersion: j['app_version'] as String?,
      noMatch: j['phone_no_match'] == true,
      phoneTries: ((j['phone_tries'] as List?) ?? const []).map((v) => (v as num).toDouble()).toList(growable: false),
    );
  }

  /// Never prints the face code or the photo.
  @override
  String toString() => 'OfflinePunch($direction at $takenAt)';
}

/// What the server said about one offline punch once it arrived.
class OfflineSendResult {
  final String clientUuid;
  final String direction;
  final DateTime takenAt;

  /// accepted | approved | review | rejected | superseded — or `refused` when the
  /// server would not take it at all (e.g. the same face capture twice).
  final String status;
  final String message;
  final String? reviewReason;

  const OfflineSendResult({
    required this.clientUuid,
    required this.direction,
    required this.takenAt,
    required this.status,
    required this.message,
    this.reviewReason,
  });

  bool get recorded => status == 'accepted' || status == 'approved' || status == 'superseded';

  factory OfflineSendResult.fromServer(OfflinePunch p, Map<String, dynamic> j) => OfflineSendResult(
        clientUuid: p.clientUuid,
        direction: p.direction,
        takenAt: p.takenAt,
        status: (j['status'] ?? 'review') as String,
        message: (j['message'] ?? '') as String,
        reviewReason: j['review_reason'] as String?,
      );

  /// One sentence for the Time Clock, e.g. "Your offline Time In of Nov 24, 7:58 AM
  /// was recorded."
  String get sentence {
    final what = direction == 'in' ? 'Time In' : 'Time Out';
    final when = '${ManilaTime.dateOnly(localDateOf(takenAt))}, ${ManilaTime.time(takenAt)}';
    return switch (status) {
      'accepted' || 'approved' => 'Your offline $what of $when was recorded.',
      'superseded' => 'Your offline $what of $when was received; the day already had it.',
      'review' => 'Your offline $what of $when was received and is waiting for HR to check it'
          '${reviewReason == null ? '.' : ': $reviewReason'}',
      'rejected' => 'HR did not accept your offline $what of $when.',
      _ => 'Your offline $what of $when could not be sent: $message',
    };
  }

  static String localDateOf(DateTime utc) => ManilaTime.toManila(utc).toIso8601String().substring(0, 10);
}
