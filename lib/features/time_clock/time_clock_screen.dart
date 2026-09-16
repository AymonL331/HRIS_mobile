import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/session_controller.dart';
import '../../core/time/manila_time.dart';
import '../../shared/button_styles.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/message_banner.dart';
import '../../shared/widgets/status_badge.dart';
import '../consent/consent_screen.dart';
import '../face/face_capture_screen.dart';
import '../face/face_models.dart';
import '../face_enrollment/enrollment_outcome_banner.dart';
import '../face_enrollment/face_enrollment_api.dart';
import '../face_enrollment/face_enrollment_models.dart';
import '../face_enrollment/face_enrollment_screen.dart';
import '../tracking/tracking_service.dart';
import '../tracking/tracking_status_card.dart';
import 'clock_models.dart';
import 'time_clock_controller.dart';

/// How often the Time Clock re-reads itself while HR can still change what it offers
/// (an open face-enrollment pass, a submission under review). Public for the tests.
abstract final class TimeClockScreenPoll {
  static const interval = Duration(seconds: 45);
}

/// The home tab. Server time ticking, today's punches, the worksite range, the
/// two big buttons, and the outcome of the last tap — laid out like the web
/// My Time Clock page: a centred hero card, then the cards beneath it.
class TimeClockScreen extends StatefulWidget {
  /// Replaces the real face-capture screen. Only the widget tests pass this —
  /// they cannot run a WebView or a camera, and the punch flow around the face
  /// check is what those tests are about.
  @visibleForTesting
  final FaceCapturer? captureOverride;

  /// Replace the enrollment API and capture (server migration 061) — tests only.
  @visibleForTesting
  final FaceEnrollmentApi? enrollmentApiOverride;
  @visibleForTesting
  final EnrollmentCapturer? enrollmentCaptureOverride;

  /// Opens the Profile Photo destination — the first step for an employee who has
  /// no photo on file yet (server 2026-09-16). The shell supplies it.
  final VoidCallback? onOpenProfilePhoto;

  const TimeClockScreen({
    super.key,
    this.captureOverride,
    this.enrollmentApiOverride,
    this.enrollmentCaptureOverride,
    this.onOpenProfilePhoto,
  });

  @override
  State<TimeClockScreen> createState() => _TimeClockScreenState();
}

class _TimeClockScreenState extends State<TimeClockScreen>
    with WidgetsBindingObserver {
  Timer? _ticker;
  Timer? _enrollmentPoll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
    _enrollmentPoll = Timer.periodic(
      TimeClockScreenPoll.interval,
      (_) => _pollEnrollment(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = context.read<TimeClockController>();
      if (c.status == null && !c.loading) c.load();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _enrollmentPoll?.cancel();
    super.dispose();
  }

  // Back in the app: re-read the clock. Until 2026-09-15 it only reloaded on first
  // open, after an enrollment or a punch, or on pull-to-refresh — so a pass HR had
  // cancelled kept showing "Enroll my face" until the employee refreshed by hand.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    final c = context.read<TimeClockController>();
    if (!c.busy && !c.loading) c.load(silent: true);
  }

  // While a pass is open or a submission is under review, HR can change what this
  // screen offers at any moment (cancel the pass, approve, reject) — re-read it so
  // the change shows without a manual refresh. Nothing is polled otherwise.
  void _pollEnrollment() {
    if (!mounted) return;
    final c = context.read<TimeClockController>();
    if (c.busy || c.loading) return;
    final se = c.status?.face.selfEnrollment;
    if (se == null) return;
    // …and while a PROFILE PHOTO is with HR (2026-09-16): approving it is what turns
    // this card from "waiting" into an enrollment the employee can start.
    if (se.phase == SelfEnrollmentPhase.passOpen ||
        se.phase == SelfEnrollmentPhase.pending ||
        se.profilePhotoPending) {
      c.load(silent: true);
    }
  }

  // Enroll (or re-enroll) from this phone while HR's pass is open, then reload so
  // the card reflects "waiting for review".
  Future<void> _openEnrollment(TimeClockController c) async {
    final api =
        widget.enrollmentApiOverride ??
        MobileFaceEnrollmentApi(context.read<SessionController>());
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => FaceEnrollmentScreen(
          api: api,
          passExpiresAt: c.status?.face.selfEnrollment.passExpiresAt,
          captureOverride: widget.enrollmentCaptureOverride,
        ),
      ),
    );
    if (mounted) await c.load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<TimeClockController>();
    final status = c.status;

    if (status == null && c.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (status == null) {
      return _LoadError(
        message: c.loadError ?? 'Could not load your time clock.',
        onRetry: c.load,
      );
    }
    if (!status.consentGiven) {
      return ConsentScreen(saving: c.consentSaving, onAgree: c.grantConsent);
    }
    // The clock is face-gated, so an employee with no enrolled template cannot
    // punch at all. Said HERE, on the home screen, rather than after they have
    // stood in front of a camera for twenty seconds to be refused.
    if (!status.face.canPunch) {
      return _NotEnrolled(
        state: status.face.selfEnrollment,
        onEnroll: () => _openEnrollment(c),
        onRefresh: () => c.load(silent: true),
        onOpenProfilePhoto: widget.onOpenProfilePhoto,
      );
    }
    final selfEnrollment = status.face.selfEnrollment;

    final tenant = context.read<SessionController>().tenant;
    final now = c.clock.nowUtc();

    // A Column, not a lazy list: the page has a handful of cards and the
    // outcome banner must exist the moment it is set, even below the fold.
    return RefreshIndicator(
      onRefresh: () => c.load(silent: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          HrisSpace.s4,
          HrisSpace.s2,
          HrisSpace.s4,
          HrisSpace.s5,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (c.loadError != null) ...[
              MessageBanner.warning(
                c.loadError!,
                onClose: () => c.load(silent: true),
              ),
              const SizedBox(height: HrisSpace.s3),
            ],
            _Header(
              name: status.employeeName,
              code: status.employeeCode,
              tenantName: tenant?.name,
              nowUtc: now,
            ),
            const SizedBox(height: HrisSpace.s3),
            // Already enrolled, but HR opened a pass — typically because the face they
            // enrolled on the website does not match this phone's camera.
            if (selfEnrollment.canEnroll ||
                selfEnrollment.phase == SelfEnrollmentPhase.pending) ...[
              _ReEnrollBanner(
                state: selfEnrollment,
                onEnroll: () => _openEnrollment(c),
              ),
              const SizedBox(height: HrisSpace.s3),
            ],
            // Already enrolled, and HR rejected — or the server blocked — the NEW face.
            // Without this the banner above simply vanished and the employee was never
            // told why (2026-09-15). Dismissible per submission; spaces itself.
            if (selfEnrollment.phase == SelfEnrollmentPhase.rejected ||
                selfEnrollment.phase == SelfEnrollmentPhase.blocked)
              EnrollmentOutcomeBanner(
                state: selfEnrollment,
                employeeCode: status.employeeCode,
              ),
            _TodayCard(status: status),
            const SizedBox(height: HrisSpace.s3),
            _WorksiteCard(controller: c),
            if (status.tracking.active && c.tracking != null)
              ValueListenableBuilder<TrackingSnapshot>(
                valueListenable: c.tracking!.snapshot,
                builder: (_, snap, _) => Padding(
                  padding: const EdgeInsets.only(top: HrisSpace.s3),
                  child: TrackingStatusCard(
                    state: status.tracking,
                    snapshot: snap,
                    nowUtc: now,
                    onRestart: () => c.load(silent: true),
                  ),
                ),
              ),
            const SizedBox(height: HrisSpace.s4),
            _PunchButtons(
              controller: c,
              captureOverride: widget.captureOverride,
            ),
            if (c.outcome != null) ...[
              const SizedBox(height: HrisSpace.s4),
              _OutcomeCard(
                outcome: c.outcome!,
                onDismiss: c.dismissOutcome,
                onConsent: c.grantConsent,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The hero card: who, and the server clock in Manila.
class _Header extends StatelessWidget {
  final String name;
  final String code;
  final String? tenantName;
  final DateTime nowUtc;
  const _Header({
    required this.name,
    required this.code,
    required this.tenantName,
    required this.nowUtc,
  });

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return AppCard(
      maxWidth: 440,
      centered: true,
      padding: const EdgeInsets.all(HrisSpace.s6),
      child: Column(
        children: [
          Text(
            name.isEmpty ? 'Employee' : name,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: HrisType.lg,
              fontWeight: HrisType.semibold,
              height: 1.3,
              color: t.text,
            ),
          ),
          Text(
            [if (code.isNotEmpty) code, ?tenantName].join(' · '),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: HrisType.sm,
              height: 1.4,
              color: t.muted,
            ),
          ),
          const SizedBox(height: HrisSpace.s4),
          Text(
            ManilaTime.timeWithSeconds(nowUtc),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: HrisType.stat,
              fontWeight: HrisType.semibold,
              height: 1.15,
              color: t.text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: HrisSpace.s1),
          Text(
            ManilaTime.clock(nowUtc),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: HrisType.sm, height: 1.4, color: t.text),
          ),
          Text(
            'Server time (Manila)',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: HrisType.xs,
              height: 1.4,
              color: t.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  final ClockStatus status;
  const _TodayCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final today = status.today;
    final t = HrisTokens.of(context);
    Widget stamp(String label, DateTime? at) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: HrisType.xxs,
              fontWeight: HrisType.semibold,
              height: 1.2,
              color: t.muted,
              letterSpacing: HrisType.xxs * 0.05,
            ),
          ),
          const SizedBox(height: HrisSpace.s1),
          Text(
            at == null ? '—' : ManilaTime.time(at),
            style: TextStyle(
              fontSize: HrisType.lg,
              fontWeight: HrisType.semibold,
              height: 1.3,
              color: at == null ? t.muted : t.text,
            ),
          ),
        ],
      ),
    );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Today',
                style: TextStyle(
                  fontSize: HrisType.md,
                  fontWeight: HrisType.semibold,
                  height: 1.35,
                  color: t.text,
                ),
              ),
              const Spacer(),
              Text(
                ManilaTime.shortDate(status.localDate),
                style: TextStyle(
                  fontSize: HrisType.sm,
                  height: 1.4,
                  color: t.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: HrisSpace.s3),
          Row(
            children: [
              stamp('Time in', today?.clockInAt),
              stamp('Time out', today?.clockOutAt),
            ],
          ),
          if (today?.status != null) ...[
            const SizedBox(height: HrisSpace.s3),
            Align(
              alignment: Alignment.centerLeft,
              child: StatusBadge(
                _statusLabel(today!.status!),
                tone: dtrStatusTone(today.status),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _statusLabel(String s) => switch (s) {
    'present' => 'Present',
    'late' => 'Late',
    'absent' => 'Absent',
    'official_business' => 'Official business',
    _ => s,
  };
}

/// The worksite panel: the range line as the web's verdict pill (success in
/// range, warning out of range, neutral otherwise), the fix age, and the
/// check button.
class _WorksiteCard extends StatelessWidget {
  final TimeClockController controller;
  const _WorksiteCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    final ws = controller.status!.worksite;
    final fix = controller.lastFix;
    final range = controller.range;
    final t = HrisTokens.of(context);

    String line;
    StatusSet? set; // null = neutral
    if (!ws.configured) {
      line = 'No worksite configured for your branch — punches are not range-checked.';
    } else if (fix == null) {
      line =
          'Allowed radius ${ws.radiusM} m around ${ws.branchName ?? 'the worksite'}.';
    } else if (range.within == true) {
      line =
          'In range — ${range.distanceM} m from ${ws.branchName ?? 'the worksite'} (limit ${ws.radiusM} m).';
      set = t.success;
    } else {
      line =
          'Out of range — ${range.distanceM} m from ${ws.branchName ?? 'the worksite'} (limit ${ws.radiusM} m).';
      set = t.warning;
    }
    final pillBg = set?.bg ?? Color.alphaBlend(t.hover, t.surface);
    final pillBorder = set?.border ?? t.border;
    final pillText = set?.text ?? t.muted;

    return AppCard(
      padding: const EdgeInsets.all(HrisSpace.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            ws.configured ? Icons.place_outlined : Icons.location_searching,
            color: set?.text ?? t.muted,
          ),
          const SizedBox(width: HrisSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: HrisSpace.s3,
                    vertical: HrisSpace.s2,
                  ),
                  decoration: BoxDecoration(
                    color: pillBg,
                    border: Border.all(color: pillBorder),
                    borderRadius: BorderRadius.circular(HrisRadius.sm),
                  ),
                  child: Text(
                    line,
                    style: TextStyle(
                      fontSize: HrisType.sm,
                      fontWeight: HrisType.semibold,
                      height: 1.4,
                      color: pillText,
                    ),
                  ),
                ),
                if (fix != null) ...[
                  const SizedBox(height: HrisSpace.s1),
                  Text(
                    'GPS ±${fix.accuracyM.round()} m · ${_age(fix.at)}',
                    style: TextStyle(
                      fontSize: HrisType.xs,
                      height: 1.4,
                      color: t.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (ws.configured) ...[
            const SizedBox(width: HrisSpace.s1),
            IconButton(
              tooltip: 'Check my range',
              onPressed: controller.rangeChecking || controller.busy
                  ? null
                  : controller.checkRange,
              icon: controller.rangeChecking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
            ),
          ],
        ],
      ),
    );
  }

  static String _age(DateTime at) {
    final s = DateTime.now().difference(at).inSeconds;
    if (s < 5) return 'just now';
    if (s < 60) return '${s}s ago';
    return '${s ~/ 60} min ago';
  }
}

/// The two big buttons, stacked full width like the web `.directions` column:
/// Time In primary, Time Out secondary (a FilledButton in the secondary
/// clothes — the tests find both by type).
class _PunchButtons extends StatelessWidget {
  final TimeClockController controller;
  final FaceCapturer? captureOverride;
  const _PunchButtons({required this.controller, this.captureOverride});

  @override
  Widget build(BuildContext context) {
    final s = controller.status!;
    final busy = controller.busy;
    final t = HrisTokens.of(context);
    final phaseText = switch (controller.phase) {
      ClockPhase.locating => 'Getting your location…',
      ClockPhase.verifyingFace => 'Checking your face…',
      ClockPhase.submitting => 'Recording…',
      ClockPhase.idle => null,
    };

    // Pushes the face check and hands its result back to the controller. Lives
    // here because only the widget tree can present a screen; the controller
    // stays testable without a camera.
    Future<FaceResult> capture(String direction) async {
      final override = captureOverride;
      if (override != null) return override(direction);
      final result = await Navigator.of(context).push<FaceResult>(
        MaterialPageRoute<FaceResult>(
          builder: (_) => FaceCaptureScreen(
            direction: direction,
            issueChallenge: controller.api.faceChallenge,
          ),
          fullscreenDialog: true,
        ),
      );
      // A dismissed route (system back, no result) is a cancel, not a punch.
      return result ?? const FaceFailed(FaceFailure.cancelled);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: !busy && s.canClockIn
              ? () => controller.punch('in', capture: capture)
              : null,
          icon: const Icon(Icons.login),
          label: const Text('Time In'),
          style: HrisButtonStyles.primaryLg(context),
        ),
        const SizedBox(height: HrisSpace.s3),
        FilledButton.tonalIcon(
          onPressed: !busy && s.canClockOut
              ? () => controller.punch('out', capture: capture)
              : null,
          icon: const Icon(Icons.logout),
          label: const Text('Time Out'),
          style: HrisButtonStyles.secondaryLg(context),
        ),
        if (phaseText != null) ...[
          const SizedBox(height: HrisSpace.s3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: HrisSpace.s2 + 2),
              Text(
                phaseText,
                style: TextStyle(
                  fontSize: HrisType.sm,
                  height: 1.4,
                  color: t.muted,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The outcome of the last tap: the web's success / fail mark above the
/// message banner. The stamped time lives in the one banner sentence.
class _OutcomeCard extends StatelessWidget {
  final PunchOutcome outcome;
  final VoidCallback onDismiss;
  final VoidCallback onConsent;
  const _OutcomeCard({
    required this.outcome,
    required this.onDismiss,
    required this.onConsent,
  });

  Widget _mark(BuildContext context, {required bool ok}) {
    final t = HrisTokens.of(context);
    return Center(
      child: Container(
        width: HrisSpace.s6,
        height: HrisSpace.s6,
        decoration: BoxDecoration(
          color: ok ? t.success.solid : t.danger.solid,
          shape: BoxShape.circle,
        ),
        child: Icon(
          ok ? Icons.check : Icons.priority_high,
          size: 20,
          color: t.primaryContrast,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (outcome) {
      case PunchSuccess(:final response, :final warnLowAccuracy):
        final at = response.stampedAt;
        final what = response.direction == 'in' ? 'Timed in' : 'Timed out';
        final parts = <String>[
          if (at != null) '$what at ${ManilaTime.time(at)}.',
          if (response.within == true && response.distanceM != null)
            'In range (${response.distanceM} m from the worksite).',
          if (response.within == false && response.distanceM != null)
            'Out of range (${response.distanceM} m from the worksite) — this punch is flagged for HR.',
          if (response.flagged && response.within != false)
            'Flagged for HR: ${response.flagReason ?? 'see DTR'}.',
          if (warnLowAccuracy)
            'Your GPS reading was coarse, so the punch is flagged for review.',
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _mark(context, ok: true),
            const SizedBox(height: HrisSpace.s3),
            MessageBanner.success(parts.join(' '), onClose: onDismiss),
          ],
        );
      case PunchInfo(:final message):
        return MessageBanner.info(message, onClose: onDismiss);
      case PunchBlocked(:final message):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _mark(context, ok: false),
            const SizedBox(height: HrisSpace.s3),
            MessageBanner.error(
              '$message Move closer to your worksite and try again.',
              onClose: onDismiss,
            ),
          ],
        );
      case PunchFailure(:final message):
        return MessageBanner.error(message, onClose: onDismiss);
      case PunchNeedsConsent():
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const MessageBanner.warning(
              'Your location consent is not on record yet.',
            ),
            const SizedBox(height: HrisSpace.s2),
            OutlinedButton(
              onPressed: onConsent,
              child: const Text('Review and give consent'),
            ),
          ],
        );
    }
  }
}

class _LoadError extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _LoadError({required this.message, required this.onRetry});

  @override
  // Also pullable: a failed load is the other moment a reader reaches for refresh.
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: onRetry,
    child: LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(HrisSpace.s4),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.maxHeight - HrisSpace.s4 * 2,
          ),
          child: Center(
            child: AppCard(
              tone: AppCardTone.danger,
              maxWidth: 440,
              centered: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MessageBanner.error(message),
                  const SizedBox(height: HrisSpace.s3),
                  OutlinedButton(
                    onPressed: () => onRetry(),
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Shown instead of the clock when the signed-in employee has no active face
/// template. The mobile clock is face-gated (2026-09-13), so they cannot punch —
/// but since migration 061 they may be able to enroll right here: the card follows
/// the server's self-enrollment state instead of always saying "ask HR".
class _NotEnrolled extends StatelessWidget {
  final SelfEnrollmentState state;
  final VoidCallback onEnroll;

  /// Re-reads the clock. A Future, because this card can also be PULLED down to
  /// refresh (user, 2026-09-16: while waiting on HR the only way to see a change
  /// was to close and reopen the app).
  final Future<void> Function() onRefresh;

  /// Opens the Profile Photo page. Null in a context that cannot navigate (tests).
  final VoidCallback? onOpenProfilePhoto;

  const _NotEnrolled({
    required this.state,
    required this.onEnroll,
    required this.onRefresh,
    this.onOpenProfilePhoto,
  });

  /// NOTHING can be enrolled before HR has a photo to compare it with (server
  /// 2026-09-16), so a new employee's first instruction is that photo — not "ask
  /// HR", which was the old dead end. Only while there is nothing under review:
  /// a pending/rejected/blocked submission has its own thing to say.
  bool get _photoStep =>
      !state.profilePhotoOnFile &&
      (state.phase == SelfEnrollmentPhase.none ||
          state.phase == SelfEnrollmentPhase.passOpen);

  /// The photo is sent and with HR: say so, rather than asking for it again.
  bool get _photoWaiting => _photoStep && state.profilePhotoPending;
  bool get _photoFirst => _photoStep && !state.profilePhotoPending;

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final (IconData icon, String title, String body) = _photoWaiting
        ? (
            Icons.hourglass_top_outlined,
            'Waiting for HR to check your photo',
            'Your profile photo has been sent. Once HR approves it, they can allow face enrollment on this '
                'phone — then you can enroll your face and this screen becomes your time clock. Pull down to '
                'check again.',
          )
        : _photoFirst
        ? (
            Icons.account_circle_outlined,
            'Send your profile photo first',
            'Before your face can be enrolled, HR needs a photo of you to compare it with. Open the menu, '
                'choose Profile Photo and take one. Once HR approves it, they can allow face enrollment on '
                'this phone — then this screen becomes your time clock.',
          )
        : switch (state.phase) {
            SelfEnrollmentPhase.passOpen => (
              Icons.face_outlined,
              'Enroll your face',
              'HR has allowed you to enroll your face on this phone'
                  '${state.passExpiresAt != null ? ' until ${ManilaTime.dateTime(state.passExpiresAt!)}' : ''}. '
                  'It takes about a minute. Once HR approves it, this screen becomes your time clock.',
            ),
            SelfEnrollmentPhase.pending => (
              Icons.hourglass_top_outlined,
              'Waiting for HR review',
              'You enrolled your face${state.submittedAt != null ? ' on ${ManilaTime.dateTime(state.submittedAt!)}' : ''}. '
                  'HR will compare the photo with your profile; once they approve it, this screen becomes your time clock.',
            ),
            SelfEnrollmentPhase.rejected => (
              Icons.face_retouching_off_outlined,
              'Face enrollment not approved',
              '${state.reason != null && state.reason!.isNotEmpty ? 'Reason: ${state.reason}\n\n' : ''}'
                  'Ask HR to allow face enrollment again, then try in good light, facing the camera.',
            ),
            SelfEnrollmentPhase.blocked => (
              Icons.face_retouching_off_outlined,
              'Face enrollment not accepted',
              '${state.reason ?? "This face couldn't be accepted for your account."} Ask HR.',
            ),
            SelfEnrollmentPhase.none => (
              Icons.face_retouching_off_outlined,
              'Face not enrolled yet',
              'Clocking in and out from the app is verified by face recognition, and your face has not been '
                  'enrolled yet. Ask HR to enroll you or to allow face enrollment on your phone — then this screen '
                  'becomes your time clock.',
            ),
          };

    // PULLABLE, even though it is one short card: waiting on HR is exactly when a
    // reader reaches for a refresh, and a card with nothing to scroll gives the
    // gesture nowhere to start — hence the always-scrollable physics and the
    // full-height box under it.
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(HrisSpace.s4),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - HrisSpace.s4 * 2,
            ),
            child: Center(
              child: AppCard(
                maxWidth: 440,
                centered: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: HrisSpace.s5,
                  vertical: HrisSpace.s6,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 40,
                      color: (state.canEnroll && !_photoStep) || _photoFirst
                          ? t.primary
                          : t.muted,
                    ),
                    const SizedBox(height: HrisSpace.s3),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: HrisType.lg,
                        fontWeight: HrisType.semibold,
                        height: 1.3,
                        color: t.text,
                      ),
                    ),
                    const SizedBox(height: HrisSpace.s2),
                    Text(
                      body,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: HrisType.sm,
                        height: 1.5,
                        color: t.muted,
                      ),
                    ),
                    if (_photoWaiting) ...[
                      const SizedBox(height: HrisSpace.s4),
                      OutlinedButton(
                        onPressed: () => onRefresh(),
                        child: const Text('Check again'),
                      ),
                    ],
                    if (_photoFirst && onOpenProfilePhoto != null) ...[
                      const SizedBox(height: HrisSpace.s5),
                      FilledButton.icon(
                        onPressed: onOpenProfilePhoto,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('Open Profile Photo'),
                      ),
                    ],
                    if (!_photoStep && state.canEnroll) ...[
                      const SizedBox(height: HrisSpace.s5),
                      FilledButton(
                        onPressed: onEnroll,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                        child: const Text('Enroll my face'),
                      ),
                    ],
                    if (state.phase == SelfEnrollmentPhase.pending) ...[
                      const SizedBox(height: HrisSpace.s4),
                      OutlinedButton(
                        onPressed: () => onRefresh(),
                        child: const Text('Check again'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// On the clock itself, for an employee who IS enrolled: HR opened a pass to
/// re-enroll on this phone, or the new enrollment is waiting for review.
class _ReEnrollBanner extends StatelessWidget {
  final SelfEnrollmentState state;
  final VoidCallback onEnroll;

  const _ReEnrollBanner({required this.state, required this.onEnroll});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final pending = state.phase == SelfEnrollmentPhase.pending;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            pending
                ? 'New face enrollment waiting for HR review'
                : 'HR allowed you to re-enroll your face',
            style: TextStyle(
              fontSize: HrisType.md,
              fontWeight: HrisType.semibold,
              color: t.text,
            ),
          ),
          const SizedBox(height: HrisSpace.s1),
          Text(
            pending
                ? 'Keep clocking as usual; your new face takes over once HR approves it.'
                : 'Do this if the app has trouble recognising you on this phone'
                      '${state.passExpiresAt != null ? ' (until ${ManilaTime.dateTime(state.passExpiresAt!)})' : ''}.',
            style: TextStyle(
              fontSize: HrisType.sm,
              height: 1.45,
              color: t.muted,
            ),
          ),
          if (!pending) ...[
            const SizedBox(height: HrisSpace.s3),
            OutlinedButton(
              onPressed: onEnroll,
              child: const Text('Re-enroll on this phone'),
            ),
          ],
        ],
      ),
    );
  }
}
