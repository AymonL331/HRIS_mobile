import '../../core/time/manila_time.dart';

/// Where the last profile photo I sent stands (server migration 062).
enum ProfilePhotoPhase {
  /// Nothing sent (or only photos I replaced before anyone decided).
  none,

  /// Waiting for HR; my current photo stays until they approve.
  pending,

  /// HR did not approve it — [ProfilePhotoState.reason] says why.
  rejected,

  /// HR approved it: it is my profile photo now.
  approved,
}

/// `GET /api/me/profile-photo`.
class ProfilePhotoState {
  /// Path of my current profile photo on the server (`/api/uploads/...`), or null.
  final String? profileImageUrl;
  final ProfilePhotoPhase phase;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final String? reason;

  const ProfilePhotoState({
    required this.phase,
    this.profileImageUrl,
    this.submittedAt,
    this.reviewedAt,
    this.reason,
  });

  static const empty = ProfilePhotoState(phase: ProfilePhotoPhase.none);

  factory ProfilePhotoState.fromJson(Map<String, dynamic>? j) {
    if (j == null) return empty;
    final phase = switch (j['state']) {
      'pending' => ProfilePhotoPhase.pending,
      'rejected' => ProfilePhotoPhase.rejected,
      'approved' => ProfilePhotoPhase.approved,
      _ => ProfilePhotoPhase.none,
    };
    final url = j['profile_image_url'];
    return ProfilePhotoState(
      phase: phase,
      profileImageUrl: url is String && url.isNotEmpty ? url : null,
      submittedAt: ManilaTime.parseUtc(j['submitted_at'] as String?),
      reviewedAt: ManilaTime.parseUtc(j['reviewed_at'] as String?),
      reason: j['reason'] as String?,
    );
  }
}
