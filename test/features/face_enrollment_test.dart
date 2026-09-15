import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/auth/session_controller.dart';
import 'package:hris_mobile/core/auth/session_store.dart';
import 'package:hris_mobile/core/config/env_store.dart';
import 'package:hris_mobile/core/http/api_exception.dart';
import 'package:hris_mobile/features/face/face_capture_screen.dart';
import 'package:hris_mobile/features/face/face_models.dart';
import 'package:hris_mobile/features/face_enrollment/face_enrollment_api.dart';
import 'package:hris_mobile/features/face_enrollment/face_enrollment_models.dart';
import 'package:hris_mobile/features/face_enrollment/face_enrollment_screen.dart';
import 'package:hris_mobile/features/time_clock/clock_models.dart';
import 'package:hris_mobile/features/time_clock/time_clock_controller.dart';
import 'package:hris_mobile/features/time_clock/time_clock_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/clock_fakes.dart';

// FACE SELF-ENROLLMENT from this phone (server migration 061). What matters: the
// server's state reads as the right card (never a dead end when HR opened a pass),
// the photo never leaks into a log line, the flow is consent -> capture -> submit ->
// "sent for review", and the server's refusal (a face that belongs to someone else)
// is shown in its own words.

class FakeFaceEnrollmentApi implements FaceEnrollmentApi {
  final List<FaceCapture> submits = [];
  ApiException? submitError;
  int challenges = 0;

  @override
  Future<FaceChallenge> challenge() async {
    challenges += 1;
    return FaceChallenge(nonce: 'b' * 64, actions: const ['blink']);
  }

  @override
  Future<void> submit(FaceCapture capture) async {
    if (submitError != null) throw submitError!;
    submits.add(capture);
  }
}

FaceCapture enrollmentCapture({String? photo = 'AAAA'}) => FaceCapture(
      nonce: 'c' * 64,
      embedding: List<double>.generate(128, (i) => i / 128),
      dims: 128,
      modelVersion: 'human-3',
      completedChallenges: const ['blink'],
      photoJpegBase64: photo,
    );

Future<({TimeClockController controller, FakeClockApi api})> mountClock(
  WidgetTester tester, {
  required Map<String, dynamic> status,
  required FakeFaceEnrollmentApi enrollment,
  EnrollmentCapturer? capture,
}) async {
  SharedPreferences.setMockInitialValues({});
  final env = EnvStore();
  await env.load();
  final session = SessionController(env: env, store: InMemorySessionStore(), appVersion: '1');
  final api = FakeClockApi()..status_ = status;
  final controller = TimeClockController(api: api, fixes: FakeFixService());
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<SessionController>.value(value: session),
      ChangeNotifierProvider<TimeClockController>.value(value: controller),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: TimeClockScreen(
          captureOverride: FakeFaceCapturer().call,
          enrollmentApiOverride: enrollment,
          enrollmentCaptureOverride: capture ?? () async => FaceCaptured(enrollmentCapture()),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return (controller: controller, api: api);
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('the self-enrollment state the server describes', () {
    test('each server state maps to its phase; a missing block is "none"', () {
      expect(SelfEnrollmentState.fromJson(null).phase, SelfEnrollmentPhase.none);
      final open = SelfEnrollmentState.fromJson({'state': 'pass_open', 'pass_expires_at': '2026-09-17T09:00:00.000Z'});
      expect(open.phase, SelfEnrollmentPhase.passOpen);
      expect(open.canEnroll, isTrue);
      expect(open.passExpiresAt, DateTime.utc(2026, 9, 17, 9));
      expect(SelfEnrollmentState.fromJson({'state': 'pending'}).phase, SelfEnrollmentPhase.pending);
      expect(SelfEnrollmentState.fromJson({'state': 'rejected', 'reason': 'Too dark'}).reason, 'Too dark');
      expect(SelfEnrollmentState.fromJson({'state': 'blocked'}).phase, SelfEnrollmentPhase.blocked);
      expect(SelfEnrollmentState.fromJson({'state': 'something new'}).phase, SelfEnrollmentPhase.none);
    });

    test('the clock status carries it under face.self_enrollment', () {
      final s = ClockStatus.fromJson(statusJson(faceEnrolled: false, selfEnrollment: {'state': 'pass_open'}));
      expect(s.face.selfEnrollment.canEnroll, isTrue);
    });
  });

  group('the enrollment capture model', () {
    test('the body carries consent and the JPEG; toString never shows the photo or the vector', () {
      final capture = enrollmentCapture(photo: 'SECRETPHOTO');
      final body = capture.toEnrollmentJson();
      expect(body['consent_given'], isTrue);
      expect(body['liveness_passed'], isTrue);
      expect(body['photo'], {'type': 'image/jpeg', 'data': 'SECRETPHOTO'});
      expect(capture.toString(), isNot(contains('SECRETPHOTO')));
      expect(capture.hasPhoto, isTrue);
    });

    test('no photo, or one over the size cap, is not a usable enrollment', () {
      expect(enrollmentCapture(photo: null).hasPhoto, isFalse);
      expect(enrollmentCapture(photo: 'A' * (FaceCapture.maxPhotoBase64Length + 1)).hasPhoto, isFalse);
    });
  });

  group('the Time Clock cards', () {
    testWidgets('no pass: told to ask HR, and nothing to tap', (tester) async {
      await mountClock(tester, status: statusJson(faceEnrolled: false), enrollment: FakeFaceEnrollmentApi());
      expect(find.text('Face not enrolled yet'), findsOneWidget);
      expect(find.textContaining('allow face enrollment on your phone'), findsOneWidget);
      expect(find.text('Enroll my face'), findsNothing);
    });

    testWidgets('waiting for review: says so, with a way to check again', (tester) async {
      await mountClock(
        tester,
        status: statusJson(faceEnrolled: false, selfEnrollment: {'state': 'pending', 'submitted_at': '2026-09-14T09:40:00.000Z'}),
        enrollment: FakeFaceEnrollmentApi(),
      );
      expect(find.text('Waiting for HR review'), findsOneWidget);
      expect(find.text('Check again'), findsOneWidget);
      expect(find.text('Enroll my face'), findsNothing);
    });

    testWidgets("rejected: shows HR's reason", (tester) async {
      await mountClock(
        tester,
        status: statusJson(faceEnrolled: false, selfEnrollment: {'state': 'rejected', 'reason': 'Photo too dark'}),
        enrollment: FakeFaceEnrollmentApi(),
      );
      expect(find.text('Face enrollment not approved'), findsOneWidget);
      expect(find.textContaining('Photo too dark'), findsOneWidget);
    });

    testWidgets('an enrolled employee with an open pass sees "Re-enroll on this phone" above the clock', (tester) async {
      await mountClock(
        tester,
        status: statusJson(selfEnrollment: {'state': 'pass_open'}),
        enrollment: FakeFaceEnrollmentApi(),
      );
      expect(find.text('Time In'), findsOneWidget);
      expect(find.text('Re-enroll on this phone'), findsOneWidget);
    });
  });

  group('the enrollment flow', () {
    testWidgets('pass open: consent -> capture -> submit -> "Sent to HR for review" -> back, status reloaded', (tester) async {
      final enrollment = FakeFaceEnrollmentApi();
      final mounted = await mountClock(
        tester,
        status: statusJson(faceEnrolled: false, selfEnrollment: {'state': 'pass_open', 'pass_expires_at': '2026-09-17T09:00:00.000Z'}),
        enrollment: enrollment,
      );
      final loadsBefore = mounted.api.statusCalls;

      await tester.tap(find.text('Enroll my face'));
      await settle(tester);
      expect(find.text('Enroll your face'), findsOneWidget);
      expect(find.textContaining('RA 10173'), findsOneWidget);
      expect(enrollment.submits, isEmpty, reason: 'nothing is sent before consent');

      // The consent card is taller than the test viewport: scroll the button in first.
      await tester.ensureVisible(find.text('I agree — enroll my face'));
      await tester.tap(find.text('I agree — enroll my face'));
      await settle(tester);
      expect(enrollment.submits, hasLength(1));
      expect(enrollment.submits.single.hasPhoto, isTrue);
      expect(find.text('Sent to HR for review'), findsOneWidget);

      await tester.ensureVisible(find.text('Done'));
      await tester.tap(find.text('Done'));
      await settle(tester);
      expect(find.text('Sent to HR for review'), findsNothing);
      expect(mounted.api.statusCalls, greaterThan(loadsBefore));
    });

    testWidgets("a face that belongs to someone else: the server's words, and a way to try again", (tester) async {
      final enrollment = FakeFaceEnrollmentApi()
        ..submitError = const ApiException(
          status: 409,
          code: 'FACE_ENROLLMENT_BLOCKED',
          message: "This face can't be enrolled on your account. HR has been notified.",
        );
      await mountClock(
        tester,
        status: statusJson(faceEnrolled: false, selfEnrollment: {'state': 'pass_open'}),
        enrollment: enrollment,
      );
      await tester.tap(find.text('Enroll my face'));
      await settle(tester);
      // The consent card is taller than the test viewport: scroll the button in first.
      await tester.ensureVisible(find.text('I agree — enroll my face'));
      await tester.tap(find.text('I agree — enroll my face'));
      await settle(tester);

      expect(find.textContaining("can't be enrolled on your account"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('cancelling the camera returns to the consent card and sends nothing', (tester) async {
      final enrollment = FakeFaceEnrollmentApi();
      await mountClock(
        tester,
        status: statusJson(faceEnrolled: false, selfEnrollment: {'state': 'pass_open'}),
        enrollment: enrollment,
        capture: () async => const FaceFailed(FaceFailure.cancelled),
      );
      await tester.tap(find.text('Enroll my face'));
      await settle(tester);
      // The consent card is taller than the test viewport: scroll the button in first.
      await tester.ensureVisible(find.text('I agree — enroll my face'));
      await tester.tap(find.text('I agree — enroll my face'));
      await settle(tester);

      expect(find.text('I agree — enroll my face'), findsOneWidget);
      expect(enrollment.submits, isEmpty);
    });

    testWidgets('a capture without its photo is refused on-device, never uploaded', (tester) async {
      final enrollment = FakeFaceEnrollmentApi();
      await mountClock(
        tester,
        status: statusJson(faceEnrolled: false, selfEnrollment: {'state': 'pass_open'}),
        enrollment: enrollment,
        capture: () async => FaceCaptured(enrollmentCapture(photo: null)),
      );
      await tester.tap(find.text('Enroll my face'));
      await settle(tester);
      // The consent card is taller than the test viewport: scroll the button in first.
      await tester.ensureVisible(find.text('I agree — enroll my face'));
      await tester.tap(find.text('I agree — enroll my face'));
      await settle(tester);

      expect(enrollment.submits, isEmpty);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  test('the capture screen can be titled and asked for the frame (enrollment)', () {
    final screen = FaceCaptureScreen(
      direction: 'enroll',
      title: 'Face enrollment',
      includeFrame: true,
      issueChallenge: (_) async => const FaceChallenge(nonce: '', actions: []),
    );
    expect(screen.includeFrame, isTrue);
    expect(screen.title, 'Face enrollment');
  });
}
