import '../../core/time/manila_time.dart';

/// Where this employee stands with FACE SELF-ENROLLMENT (server migration 061),
/// as the server reports it in `face.self_enrollment` on the clock status.
enum SelfEnrollmentPhase {
  /// No pass from HR, nothing submitted.
  none,

  /// HR opened a one-time pass: the employee may enroll their face now.
  passOpen,

  /// A submission is waiting for HR to compare the photo and approve.
  pending,

  /// HR rejected the last submission ([SelfEnrollmentState.reason] says why).
  rejected,

  /// The last submission's face already belongs to another employee.
  blocked,
}

class SelfEnrollmentState {
  final SelfEnrollmentPhase phase;
  final DateTime? passExpiresAt;
  final DateTime? submittedAt;
  final String? reason;

  const SelfEnrollmentState({
    required this.phase,
    this.passExpiresAt,
    this.submittedAt,
    this.reason,
  });

  static const none = SelfEnrollmentState(phase: SelfEnrollmentPhase.none);

  factory SelfEnrollmentState.fromJson(Map<String, dynamic>? j) {
    // A server that predates migration 061 sends no block: nothing to offer.
    if (j == null) return none;
    final phase = switch (j['state']) {
      'pass_open' => SelfEnrollmentPhase.passOpen,
      'pending' => SelfEnrollmentPhase.pending,
      'rejected' => SelfEnrollmentPhase.rejected,
      'blocked' => SelfEnrollmentPhase.blocked,
      _ => SelfEnrollmentPhase.none,
    };
    return SelfEnrollmentState(
      phase: phase,
      passExpiresAt: ManilaTime.parseUtc(j['pass_expires_at'] as String?),
      submittedAt: ManilaTime.parseUtc(j['submitted_at'] as String?),
      reason: j['reason'] as String?,
    );
  }

  bool get canEnroll => phase == SelfEnrollmentPhase.passOpen;
}
