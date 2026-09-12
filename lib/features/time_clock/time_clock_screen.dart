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
import 'clock_models.dart';
import 'time_clock_controller.dart';

/// The home tab. Server time ticking, today's punches, the worksite range, the
/// two big buttons, and the outcome of the last tap — laid out like the web
/// My Time Clock page: a centred hero card, then the cards beneath it.
class TimeClockScreen extends StatefulWidget {
  /// Replaces the real face-capture screen. Only the widget tests pass this —
  /// they cannot run a WebView or a camera, and the punch flow around the face
  /// check is what those tests are about.
  @visibleForTesting
  final FaceCapturer? captureOverride;

  const TimeClockScreen({super.key, this.captureOverride});

  @override
  State<TimeClockScreen> createState() => _TimeClockScreenState();
}

class _TimeClockScreenState extends State<TimeClockScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = context.read<TimeClockController>();
      if (c.status == null && !c.loading) c.load();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<TimeClockController>();
    final status = c.status;

    if (status == null && c.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (status == null) {
      return _LoadError(message: c.loadError ?? 'Could not load your time clock.', onRetry: c.load);
    }
    if (!status.consentGiven) {
      return ConsentScreen(saving: c.consentSaving, onAgree: c.grantConsent);
    }
    // The clock is face-gated, so an employee with no enrolled template cannot
    // punch at all. Said HERE, on the home screen, rather than after they have
    // stood in front of a camera for twenty seconds to be refused.
    if (!status.face.canPunch) {
      return const _NotEnrolled();
    }

    final tenant = context.read<SessionController>().tenant;
    final now = c.clock.nowUtc();

    // A Column, not a lazy list: the page has a handful of cards and the
    // outcome banner must exist the moment it is set, even below the fold.
    return RefreshIndicator(
      onRefresh: () => c.load(silent: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s2, HrisSpace.s4, HrisSpace.s5),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (c.loadError != null) ...[
            MessageBanner.warning(c.loadError!, onClose: () => c.load(silent: true)),
            const SizedBox(height: HrisSpace.s3),
          ],
          _Header(name: status.employeeName, code: status.employeeCode, tenantName: tenant?.name, nowUtc: now),
          const SizedBox(height: HrisSpace.s3),
          _TodayCard(status: status),
          const SizedBox(height: HrisSpace.s3),
          _WorksiteCard(controller: c),
          const SizedBox(height: HrisSpace.s4),
          _PunchButtons(controller: c, captureOverride: widget.captureOverride),
          if (c.outcome != null) ...[
            const SizedBox(height: HrisSpace.s4),
            _OutcomeCard(outcome: c.outcome!, onDismiss: c.dismissOutcome, onConsent: c.grantConsent),
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
  const _Header({required this.name, required this.code, required this.tenantName, required this.nowUtc});

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
            style: TextStyle(fontSize: HrisType.lg, fontWeight: HrisType.semibold, height: 1.3, color: t.text),
          ),
          Text(
            [if (code.isNotEmpty) code, ?tenantName].join(' · '),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: HrisType.sm, height: 1.4, color: t.muted),
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
          Text(ManilaTime.clock(nowUtc), textAlign: TextAlign.center, style: TextStyle(fontSize: HrisType.sm, height: 1.4, color: t.text)),
          Text('Server time (Manila)', textAlign: TextAlign.center, style: TextStyle(fontSize: HrisType.xs, height: 1.4, color: t.muted)),
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
                style: TextStyle(fontSize: HrisType.xxs, fontWeight: HrisType.semibold, height: 1.2, color: t.muted, letterSpacing: HrisType.xxs * 0.05),
              ),
              const SizedBox(height: HrisSpace.s1),
              Text(
                at == null ? '—' : ManilaTime.time(at),
                style: TextStyle(fontSize: HrisType.lg, fontWeight: HrisType.semibold, height: 1.3, color: at == null ? t.muted : t.text),
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
              Text('Today', style: TextStyle(fontSize: HrisType.md, fontWeight: HrisType.semibold, height: 1.35, color: t.text)),
              const Spacer(),
              Text(ManilaTime.shortDate(status.localDate), style: TextStyle(fontSize: HrisType.sm, height: 1.4, color: t.muted)),
            ],
          ),
          const SizedBox(height: HrisSpace.s3),
          Row(children: [stamp('Time in', today?.clockInAt), stamp('Time out', today?.clockOutAt)]),
          if (today?.status != null) ...[
            const SizedBox(height: HrisSpace.s3),
            Align(
              alignment: Alignment.centerLeft,
              child: StatusBadge(_statusLabel(today!.status!), tone: dtrStatusTone(today.status)),
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
      line = 'Allowed radius ${ws.radiusM} m around ${ws.branchName ?? 'the worksite'}.';
    } else if (range.within == true) {
      line = 'In range — ${range.distanceM} m from ${ws.branchName ?? 'the worksite'} (limit ${ws.radiusM} m).';
      set = t.success;
    } else {
      line = 'Out of range — ${range.distanceM} m from ${ws.branchName ?? 'the worksite'} (limit ${ws.radiusM} m).';
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
          Icon(ws.configured ? Icons.place_outlined : Icons.location_searching, color: set?.text ?? t.muted),
          const SizedBox(width: HrisSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s3, vertical: HrisSpace.s2),
                  decoration: BoxDecoration(
                    color: pillBg,
                    border: Border.all(color: pillBorder),
                    borderRadius: BorderRadius.circular(HrisRadius.sm),
                  ),
                  child: Text(line, style: TextStyle(fontSize: HrisType.sm, fontWeight: HrisType.semibold, height: 1.4, color: pillText)),
                ),
                if (fix != null) ...[
                  const SizedBox(height: HrisSpace.s1),
                  Text(
                    'GPS ±${fix.accuracyM.round()} m · ${_age(fix.at)}',
                    style: TextStyle(fontSize: HrisType.xs, height: 1.4, color: t.muted),
                  ),
                ],
              ],
            ),
          ),
          if (ws.configured) ...[
            const SizedBox(width: HrisSpace.s1),
            IconButton(
              tooltip: 'Check my range',
              onPressed: controller.rangeChecking || controller.busy ? null : controller.checkRange,
              icon: controller.rangeChecking
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
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
          onPressed: !busy && s.canClockIn ? () => controller.punch('in', capture: capture) : null,
          icon: const Icon(Icons.login),
          label: const Text('Time In'),
          style: HrisButtonStyles.primaryLg(context),
        ),
        const SizedBox(height: HrisSpace.s3),
        FilledButton.tonalIcon(
          onPressed: !busy && s.canClockOut ? () => controller.punch('out', capture: capture) : null,
          icon: const Icon(Icons.logout),
          label: const Text('Time Out'),
          style: HrisButtonStyles.secondaryLg(context),
        ),
        if (phaseText != null) ...[
          const SizedBox(height: HrisSpace.s3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: HrisSpace.s2 + 2),
              Text(phaseText, style: TextStyle(fontSize: HrisType.sm, height: 1.4, color: t.muted)),
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
  const _OutcomeCard({required this.outcome, required this.onDismiss, required this.onConsent});

  Widget _mark(BuildContext context, {required bool ok}) {
    final t = HrisTokens.of(context);
    return Center(
      child: Container(
        width: HrisSpace.s6,
        height: HrisSpace.s6,
        decoration: BoxDecoration(color: ok ? t.success.solid : t.danger.solid, shape: BoxShape.circle),
        child: Icon(ok ? Icons.check : Icons.priority_high, size: 20, color: t.primaryContrast),
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
          if (response.within == true && response.distanceM != null) 'In range (${response.distanceM} m from the worksite).',
          if (response.within == false && response.distanceM != null)
            'Out of range (${response.distanceM} m from the worksite) — this punch is flagged for HR.',
          if (response.flagged && response.within != false) 'Flagged for HR: ${response.flagReason ?? 'see DTR'}.',
          if (warnLowAccuracy) 'Your GPS reading was coarse, so the punch is flagged for review.',
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
            MessageBanner.error('$message Move closer to your worksite and try again.', onClose: onDismiss),
          ],
        );
      case PunchFailure(:final message):
        return MessageBanner.error(message, onClose: onDismiss);
      case PunchNeedsConsent():
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const MessageBanner.warning('Your location consent is not on record yet.'),
            const SizedBox(height: HrisSpace.s2),
            OutlinedButton(onPressed: onConsent, child: const Text('Review and give consent')),
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
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(HrisSpace.s4),
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
                OutlinedButton(onPressed: () => onRetry(), child: const Text('Try again')),
              ],
            ),
          ),
        ),
      );
}

/// Shown instead of the clock when the signed-in employee has no active face
/// template. The mobile clock is face-gated (2026-09-13), so there is nothing
/// they can do from the app — the fix is HR enrolling their face on the website,
/// and saying that plainly beats a camera that refuses them.
class _NotEnrolled extends StatelessWidget {
  const _NotEnrolled();

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(HrisSpace.s4),
        child: AppCard(
          maxWidth: 440,
          centered: true,
          padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s5, vertical: HrisSpace.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.face_retouching_off_outlined, size: 40, color: t.muted),
              const SizedBox(height: HrisSpace.s3),
              Text(
                'Face not enrolled yet',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: HrisType.lg, fontWeight: HrisType.semibold, height: 1.3, color: t.text),
              ),
              const SizedBox(height: HrisSpace.s2),
              Text(
                'Clocking in and out from the app is verified by face recognition, and your face has not been '
                'enrolled yet. Ask HR to enrol you — it takes a minute at the office — and this screen becomes '
                'your time clock.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: HrisType.sm, height: 1.5, color: t.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
