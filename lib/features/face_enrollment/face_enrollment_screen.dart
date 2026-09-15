import 'package:flutter/material.dart';

import '../../core/http/api_exception.dart';
import '../../core/time/manila_time.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/message_banner.dart';
import '../face/face_capture_screen.dart';
import '../face/face_models.dart';
import 'face_enrollment_api.dart';

/// Runs one face capture for enrollment and hands back what it produced. The
/// widget tests pass a fake; the app pushes [FaceCaptureScreen].
typedef EnrollmentCapturer = Future<FaceResult> Function();

enum _Step { consent, working, done, failed }

/// Enroll your face from this phone (server migration 061), opened from the Time
/// Clock while HR's one-time pass is open.
///
/// Consent first (RA 10173: this collects a face fingerprint AND a photo, which is
/// more than the location consent covered), then the same liveness capture as a
/// punch — with the photo of the exact frame — then the upload. Nothing counts until
/// HR approves: the screen ends on "sent for review", never on "you can clock now".
class FaceEnrollmentScreen extends StatefulWidget {
  final FaceEnrollmentApi api;
  final DateTime? passExpiresAt;

  /// Replaces the real capture screen. Only the widget tests pass this — they
  /// cannot run a WebView or a camera.
  @visibleForTesting
  final EnrollmentCapturer? captureOverride;

  const FaceEnrollmentScreen({super.key, required this.api, this.passExpiresAt, this.captureOverride});

  @override
  State<FaceEnrollmentScreen> createState() => _FaceEnrollmentScreenState();
}

class _FaceEnrollmentScreenState extends State<FaceEnrollmentScreen> {
  _Step _step = _Step.consent;
  String _working = '';
  String? _error;

  Future<FaceResult> _capture() async {
    final override = widget.captureOverride;
    if (override != null) return override();
    final result = await Navigator.of(context).push<FaceResult>(
      MaterialPageRoute<FaceResult>(
        fullscreenDialog: true,
        builder: (_) => FaceCaptureScreen(
          direction: 'enroll',
          title: 'Face enrollment',
          includeFrame: true,
          issueChallenge: (_) => widget.api.challenge(),
        ),
      ),
    );
    return result ?? const FaceFailed(FaceFailure.cancelled);
  }

  Future<void> _start() async {
    setState(() {
      _step = _Step.working;
      _working = 'Opening the camera…';
      _error = null;
    });
    final result = await _capture();
    if (!mounted) return;

    switch (result) {
      case FaceFailed(reason: FaceFailure.cancelled):
        setState(() => _step = _Step.consent);
        return;
      case FaceFailed(:final reason, :final serverMessage):
        _fail(serverMessage ?? faceFailureMessage(reason));
        return;
      case FaceCaptured(:final capture):
        if (!capture.hasPhoto) {
          _fail(faceFailureMessage(FaceFailure.noEmbedding));
          return;
        }
        setState(() => _working = 'Sending your face enrollment to HR…');
        try {
          await widget.api.submit(capture);
          if (mounted) setState(() => _step = _Step.done);
        } on ApiException catch (e) {
          // The server's own words: a blocked face, an expired pass, a pending one.
          _fail(e.message);
        } catch (_) {
          _fail('Something went wrong while sending your face enrollment. Please try again.');
        }
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _step = _Step.failed;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Face enrollment')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(HrisSpace.s3),
            child: switch (_step) {
              _Step.consent => _ConsentCard(passExpiresAt: widget.passExpiresAt, onAgree: _start),
              _Step.working => _WorkingCard(text: _working),
              _Step.done => _DoneCard(onDone: () => Navigator.of(context).pop(true)),
              _Step.failed => _FailedCard(
                  message: _error ?? 'Face enrollment failed.',
                  onRetry: () => setState(() => _step = _Step.consent),
                  onClose: () => Navigator.of(context).pop(false),
                ),
            },
          ),
        ),
      ),
    );
  }
}

class _ConsentCard extends StatelessWidget {
  final DateTime? passExpiresAt;
  final VoidCallback onAgree;

  const _ConsentCard({required this.passExpiresAt, required this.onAgree});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return AppCard(
      maxWidth: 440,
      centered: true,
      padding: const EdgeInsets.all(HrisSpace.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.face_outlined, size: 40, color: t.primary),
          const SizedBox(height: HrisSpace.s3),
          Text(
            'Enroll your face',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: HrisType.heading, fontWeight: HrisType.semibold, height: 1.25, color: t.text),
          ),
          const SizedBox(height: HrisSpace.s3),
          Text(
            'HR has allowed you to enroll your face on this phone, so the app can recognise you when you clock '
            'in and out.\n\n'
            'You will blink or turn your head when asked, then look straight at the camera. The app keeps a '
            'face fingerprint and one photo of that moment, and sends both to HR. HR compares the photo with '
            'your profile before approving — until then, your current face (if any) stays in use.',
            style: TextStyle(fontSize: HrisType.sm, height: 1.5, color: t.text),
          ),
          if (passExpiresAt != null) ...[
            const SizedBox(height: HrisSpace.s2),
            Text(
              'Available until ${ManilaTime.dateTime(passExpiresAt!)}.',
              style: TextStyle(fontSize: HrisType.xs, height: 1.4, color: t.muted),
            ),
          ],
          const SizedBox(height: HrisSpace.s3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s3, vertical: HrisSpace.s2),
            decoration: BoxDecoration(
              color: Color.alphaBlend(t.hover, t.surface),
              borderRadius: BorderRadius.circular(HrisRadius.sm),
            ),
            child: Text(
              'By continuing you consent to your employer collecting your facial fingerprint and one photo for '
              'timekeeping (Data Privacy Act of 2012, RA 10173). Both are stored encrypted and seen only by HR; '
              'the photo is kept while this enrollment is in use and deleted when it is replaced or removed. To '
              'withdraw your consent, ask HR.',
              style: TextStyle(fontSize: HrisType.xs, height: 1.45, color: t.muted),
            ),
          ),
          const SizedBox(height: HrisSpace.s5),
          FilledButton(
            onPressed: onAgree,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            child: const Text('I agree — enroll my face'),
          ),
        ],
      ),
    );
  }
}

class _WorkingCard extends StatelessWidget {
  final String text;

  const _WorkingCard({required this.text});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: HrisSpace.s4),
        Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: HrisType.sm, color: t.muted)),
      ],
    );
  }
}

class _DoneCard extends StatelessWidget {
  final VoidCallback onDone;

  const _DoneCard({required this.onDone});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return AppCard(
      maxWidth: 440,
      centered: true,
      padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s5, vertical: HrisSpace.s6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.task_alt_outlined, size: 40, color: t.primary),
          const SizedBox(height: HrisSpace.s3),
          Text(
            'Sent to HR for review',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: HrisType.lg, fontWeight: HrisType.semibold, height: 1.3, color: t.text),
          ),
          const SizedBox(height: HrisSpace.s2),
          Text(
            'HR will compare your photo with your profile. Once they approve it, you can clock in and out with '
            'your face on this phone.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: HrisType.sm, height: 1.5, color: t.muted),
          ),
          const SizedBox(height: HrisSpace.s5),
          FilledButton(
            onPressed: onDone,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class _FailedCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  const _FailedCard({required this.message, required this.onRetry, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      tone: AppCardTone.danger,
      maxWidth: 440,
      centered: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MessageBanner.error(message),
          const SizedBox(height: HrisSpace.s3),
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
          const SizedBox(height: HrisSpace.s2),
          OutlinedButton(onPressed: onClose, child: const Text('Close')),
        ],
      ),
    );
  }
}
