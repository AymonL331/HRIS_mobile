import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/auth/session_controller.dart';
import 'package:hris_mobile/core/auth/session_store.dart';
import 'package:hris_mobile/core/config/env_store.dart';
import 'package:hris_mobile/core/http/api_exception.dart';
import 'package:hris_mobile/features/face/face_capture_screen.dart';
import 'package:hris_mobile/features/face/face_models.dart';
import 'package:hris_mobile/features/face_enrollment/enrollment_outcome_banner.dart';
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

  /// What the server says NOW about the pass (HR may cancel it mid-flow).
  SelfEnrollmentState current = const SelfEnrollmentState(phase: SelfEnrollmentPhase.passOpen);
  int stateCalls = 0;

  @override
  Future<SelfEnrollmentState> state() async {
    stateCalls += 1;
    return current;
  }

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
  VoidCallback? onOpenProfilePhoto,
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
          onOpenProfilePhoto: onOpenProfilePhoto,
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

    test('whether HR has a profile photo to compare against rides along; an older server means yes', () {
      // Defaulting to TRUE matters: a server without the field must not make the app
      // demand a step that server does not enforce.
      expect(SelfEnrollmentState.fromJson({'state': 'none'}).profilePhotoOnFile, isTrue);
      expect(SelfEnrollmentState.fromJson({'state': 'none', 'profile_photo_on_file': false}).profilePhotoOnFile, isFalse);
      expect(SelfEnrollmentState.fromJson({'state': 'none', 'profile_photo_on_file': true}).profilePhotoOnFile, isTrue);
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
    // A NEW employee's landing page. Before 2026-09-16 it said "ask HR" — a dead end,
    // because HR cannot open a pass until there is a profile photo to compare the
    // face against. The first step is now stated, with the way to do it.
    testWidgets('no profile photo yet: the first step is stated, and the button opens Profile Photo', (tester) async {
      var opened = 0;
      await mountClock(
        tester,
        status: statusJson(faceEnrolled: false, selfEnrollment: {'state': 'none', 'profile_photo_on_file': false}),
        enrollment: FakeFaceEnrollmentApi()..current = const SelfEnrollmentState(phase: SelfEnrollmentPhase.none),
        onOpenProfilePhoto: () => opened += 1,
      );

      expect(find.text('Send your profile photo first'), findsOneWidget);
      expect(find.textContaining('choose Profile Photo'), findsOneWidget);
      expect(find.text('Face not enrolled yet'), findsNothing);
      await tester.tap(find.text('Open Profile Photo'));
      await tester.pump();
      expect(opened, 1);
    });

    testWidgets('photo sent and with HR: the card says WAIT, and does not ask for it again', (tester) async {
      final r = await mountClock(
        tester,
        status: statusJson(
          faceEnrolled: false,
          selfEnrollment: {'state': 'none', 'profile_photo_on_file': false, 'profile_photo_pending': true},
        ),
        enrollment: FakeFaceEnrollmentApi()..current = const SelfEnrollmentState(phase: SelfEnrollmentPhase.none),
        onOpenProfilePhoto: () {},
      );

      expect(find.text('Waiting for HR to check your photo'), findsOneWidget);
      expect(find.text('Send your profile photo first'), findsNothing);
      expect(find.text('Open Profile Photo'), findsNothing);

      // …and it can be re-read without closing the app (user, 2026-09-16).
      final before = r.api.statusCalls;
      await tester.tap(find.text('Check again'));
      await settle(tester);
      expect(r.api.statusCalls, greaterThan(before));
    });

    testWidgets('the waiting card PULLS DOWN to refresh — no need to close and reopen the app', (tester) async {
      final r = await mountClock(
        tester,
        status: statusJson(
          faceEnrolled: false,
          selfEnrollment: {'state': 'none', 'profile_photo_on_file': false, 'profile_photo_pending': true},
        ),
        enrollment: FakeFaceEnrollmentApi(),
      );
      final before = r.api.statusCalls;

      await tester.fling(find.text('Waiting for HR to check your photo'), const Offset(0, 320), 1200);
      await settle(tester);
      await tester.pumpAndSettle();

      expect(r.api.statusCalls, greaterThan(before), reason: 'a pull re-reads the clock');
    });

    testWidgets('a photo IS on file: the old wording stands, and no photo button', (tester) async {
      await mountClock(
        tester,
        status: statusJson(faceEnrolled: false, selfEnrollment: {'state': 'none', 'profile_photo_on_file': true}),
        enrollment: FakeFaceEnrollmentApi()..current = const SelfEnrollmentState(phase: SelfEnrollmentPhase.none),
        onOpenProfilePhoto: () {},
      );

      expect(find.text('Face not enrolled yet'), findsOneWidget);
      expect(find.text('Open Profile Photo'), findsNothing);
    });

    testWidgets('a pass is open but the photo was removed: the photo comes first, not the camera', (tester) async {
      await mountClock(
        tester,
        status: statusJson(faceEnrolled: false, selfEnrollment: {'state': 'pass_open', 'profile_photo_on_file': false}),
        enrollment: FakeFaceEnrollmentApi(),
        onOpenProfilePhoto: () {},
      );

      expect(find.text('Send your profile photo first'), findsOneWidget);
      expect(find.text('Enroll my face'), findsNothing, reason: 'the capture would only be refused');
    });

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
      expect(find.textContaining('Reason: Photo too dark'), findsOneWidget);
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

    // 2026-09-15: for an ENROLLED employee the re-enroll banner used to vanish on
    // rejection, so they were never told why. Found in the sandbox walkthrough.
    testWidgets("an enrolled employee whose new face was rejected sees HR's reason above the clock, and can dismiss it", (tester) async {
      await mountClock(
        tester,
        status: statusJson(selfEnrollment: {'state': 'rejected', 'reason': 'Photo too dark', 'submitted_at': '2026-09-15T06:11:40.000Z'}),
        enrollment: FakeFaceEnrollmentApi(),
      );
      await settle(tester);
      expect(find.text('Time In'), findsOneWidget);
      expect(find.text('New face enrollment not approved'), findsOneWidget);
      // A plain label, not a persona (user, 2026-09-15): "Reason:", never "HR said:".
      expect(find.textContaining('Reason: Photo too dark'), findsOneWidget);
      expect(find.textContaining('HR said'), findsNothing);
      expect(find.textContaining('keep clocking with your current face'), findsOneWidget);

      await tester.tap(find.text('Dismiss'));
      await settle(tester);
      expect(find.text('New face enrollment not approved'), findsNothing);
      expect(find.text('Time In'), findsOneWidget);
    });

    testWidgets('an enrolled employee whose new face was blocked is told so, naming nobody', (tester) async {
      await mountClock(
        tester,
        status: statusJson(selfEnrollment: {
          'state': 'blocked',
          'reason': "This face couldn't be accepted for your account. Ask HR.",
          'submitted_at': '2026-09-15T06:20:00.000Z',
        }),
        enrollment: FakeFaceEnrollmentApi(),
      );
      await settle(tester);
      expect(find.text('New face enrollment not accepted'), findsOneWidget);
      expect(find.textContaining("couldn't be accepted for your account"), findsOneWidget);
      expect(find.text('Time In'), findsOneWidget);
    });

    testWidgets('a cancelled pass takes "Enroll my face" away by itself — no manual refresh', (tester) async {
      final mounted = await mountClock(
        tester,
        status: statusJson(faceEnrolled: false, selfEnrollment: {'state': 'pass_open'}),
        enrollment: FakeFaceEnrollmentApi(),
      );
      expect(find.text('Enroll my face'), findsOneWidget);

      mounted.api.status_ = statusJson(faceEnrolled: false); // HR cancelled the pass
      await tester.pump(TimeClockScreenPoll.interval + const Duration(seconds: 1));
      await settle(tester);
      expect(find.text('Enroll my face'), findsNothing);
      expect(find.text('Face not enrolled yet'), findsOneWidget);
    });

    testWidgets('coming back to the app re-reads the Time Clock', (tester) async {
      final mounted = await mountClock(tester, status: statusJson(), enrollment: FakeFaceEnrollmentApi());
      final before = mounted.api.statusCalls;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(mounted.api.statusCalls, greaterThan(before));
    });

    testWidgets('nothing to wait for: the clock is not polled', (tester) async {
      final mounted = await mountClock(tester, status: statusJson(), enrollment: FakeFaceEnrollmentApi());
      final before = mounted.api.statusCalls;
      await tester.pump(TimeClockScreenPoll.interval * 2 + const Duration(seconds: 1));
      await settle(tester);
      expect(mounted.api.statusCalls, before);
    });

    testWidgets('an enrolled employee with nothing to tell sees no outcome banner', (tester) async {
      await mountClock(tester, status: statusJson(selfEnrollment: {'state': 'none'}), enrollment: FakeFaceEnrollmentApi());
      await settle(tester);
      expect(find.textContaining('New face enrollment not'), findsNothing);
      expect(find.text('Dismiss'), findsNothing);
    });
  });

  group('dismissed enrollment notices', () {
    test('a dismissed outcome stays dismissed on this phone; a NEW submission or another employee shows again', () async {
      SharedPreferences.setMockInitialValues({});
      const store = EnrollmentNoticeStore();
      final first = SelfEnrollmentState.fromJson({'state': 'rejected', 'reason': 'x', 'submitted_at': '2026-09-15T06:09:52.000Z'});
      final second = SelfEnrollmentState.fromJson({'state': 'rejected', 'reason': 'y', 'submitted_at': '2026-09-15T06:11:40.000Z'});
      final firstKey = EnrollmentNoticeStore.noticeKey('EMP01670', first)!;

      expect(await store.isDismissed(firstKey), isFalse);
      await store.dismiss(firstKey);
      expect(await store.isDismissed(firstKey), isTrue);
      expect(await store.isDismissed(EnrollmentNoticeStore.noticeKey('EMP01670', second)!), isFalse);
      expect(await store.isDismissed(EnrollmentNoticeStore.noticeKey('EMP09999', first)!), isFalse,
          reason: 'another employee signing in on the same phone');
    });

    test('only a rejected or blocked new face has a notice', () {
      expect(EnrollmentNoticeStore.noticeKey('EMP01670', SelfEnrollmentState.none), isNull);
      expect(EnrollmentNoticeStore.noticeKey('EMP01670', SelfEnrollmentState.fromJson({'state': 'pending'})), isNull);
      expect(EnrollmentNoticeStore.noticeKey('EMP01670', SelfEnrollmentState.fromJson({'state': 'pass_open'})), isNull);
      expect(EnrollmentNoticeStore.noticeKey('EMP01670', SelfEnrollmentState.fromJson({'state': 'blocked'})), isNotNull);
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

    // 2026-09-15, found on the sandbox: HR cancelled the pass while the employee's
    // Time Clock still showed "Enroll my face".
    testWidgets('HR cancelled the pass after the clock was drawn: the screen says so and never opens the camera', (tester) async {
      final enrollment = FakeFaceEnrollmentApi()..current = SelfEnrollmentState.none;
      var captures = 0;
      final mounted = await mountClock(
        tester,
        status: statusJson(faceEnrolled: false, selfEnrollment: {'state': 'pass_open'}),
        enrollment: enrollment,
        capture: () async {
          captures += 1;
          return FaceCaptured(enrollmentCapture());
        },
      );
      mounted.api.status_ = statusJson(faceEnrolled: false); // the server's truth now
      final loadsBefore = mounted.api.statusCalls;

      await tester.tap(find.text('Enroll my face'));
      await settle(tester);
      expect(find.text('Face enrollment is not available'), findsOneWidget);
      expect(find.textContaining('the pass was cancelled or has expired'), findsOneWidget);
      expect(find.text('I agree — enroll my face'), findsNothing);
      expect(find.text('Try again'), findsNothing);
      expect(captures, 0);
      expect(enrollment.submits, isEmpty);

      await tester.tap(find.text('Back to Time Clock'));
      await settle(tester);
      expect(mounted.api.statusCalls, greaterThan(loadsBefore));
      expect(find.text('Enroll my face'), findsNothing);
      expect(find.text('Face not enrolled yet'), findsOneWidget);
    });

    testWidgets('the pass closes between consent and submit: closed, not "Try again"', (tester) async {
      final enrollment = FakeFaceEnrollmentApi()
        ..submitError = const ApiException(
          status: 422,
          code: 'FACE_ENROLLMENT_NO_PASS',
          message: 'Your face enrollment pass was already used or has expired. Ask HR for a new one.',
        );
      await mountClock(
        tester,
        status: statusJson(faceEnrolled: false, selfEnrollment: {'state': 'pass_open'}),
        enrollment: enrollment,
        capture: () async {
          enrollment.current = SelfEnrollmentState.none; // HR cancels while the camera is open
          return FaceCaptured(enrollmentCapture());
        },
      );
      await tester.tap(find.text('Enroll my face'));
      await settle(tester);
      await tester.ensureVisible(find.text('I agree — enroll my face'));
      await tester.tap(find.text('I agree — enroll my face'));
      await settle(tester);

      expect(find.text('Face enrollment is not available'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
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
