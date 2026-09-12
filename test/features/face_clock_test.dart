import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/auth/session_controller.dart';
import 'package:hris_mobile/core/auth/session_store.dart';
import 'package:hris_mobile/core/config/env_store.dart';
import 'package:hris_mobile/core/http/api_exception.dart';
import 'package:hris_mobile/core/location/location_fix.dart';
import 'package:hris_mobile/features/face/face_asset_server.dart';
import 'package:hris_mobile/features/face/face_capture_screen.dart';
import 'package:hris_mobile/features/face/face_models.dart';
import 'package:hris_mobile/features/time_clock/clock_models.dart';
import 'package:hris_mobile/features/time_clock/time_clock_controller.dart';
import 'package:hris_mobile/features/time_clock/time_clock_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/clock_fakes.dart';

Future<TimeClockController> mount(
  WidgetTester tester,
  FakeClockApi api,
  FakeFixService fixes, {
  FakeFaceCapturer? face,
}) async {
  SharedPreferences.setMockInitialValues({});
  final env = EnvStore();
  await env.load();
  final session = SessionController(env: env, store: InMemorySessionStore(), appVersion: '1');
  final controller = TimeClockController(api: api, fixes: fixes);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<SessionController>.value(value: session),
      ChangeNotifierProvider<TimeClockController>.value(value: controller),
    ],
    child: MaterialApp(home: Scaffold(body: TimeClockScreen(captureOverride: (face ?? FakeFaceCapturer()).call))),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return controller;
}

void main() {
  group('the face gate the server describes', () {
    test('required + enrolled means this employee may punch', () {
      final s = ClockStatus.fromJson(statusJson());
      expect(s.face.required, isTrue);
      expect(s.face.enrolled, isTrue);
      expect(s.face.modelVersion, 'human-3');
      expect(s.face.livenessChallenges, ['blink', 'turn_head']);
      expect(s.face.canPunch, isTrue);
    });

    test('required but NOT enrolled means they cannot punch at all', () {
      final s = ClockStatus.fromJson(statusJson(faceEnrolled: false));
      expect(s.face.canPunch, isFalse);
    });

    test('a server with no face block is treated as not requiring one', () {
      // An older deployment must keep working rather than bricking every punch.
      final s = ClockStatus.fromJson(statusJson()..remove('face'));
      expect(s.face.required, isFalse);
      expect(s.face.canPunch, isTrue);
    });
  });

  group('the capture models', () {
    test('a challenge is usable only with a 64-char nonce and at least one action', () {
      final good = FaceChallenge.fromJson({'nonce': 'a' * 64, 'challenge_types': ['blink']});
      expect(good.isUsable, isTrue);
      expect(FaceChallenge.fromJson({'nonce': 'short', 'challenge_types': ['blink']}).isUsable, isFalse);
      expect(FaceChallenge.fromJson({'nonce': 'a' * 64, 'challenge_types': []}).isUsable, isFalse);
    });

    test('the submitted body carries the nonce, the actions and liveness — and asserts liveness', () {
      final body = fakeCapture().toJson();
      expect(body['nonce'], 'a' * 64);
      expect(body['completed_challenges'], ['blink', 'turn_head']);
      expect(body['model_version'], 'human-3');
      // The server takes a STRICT boolean here and never a coerced truthy value.
      expect(body['liveness_passed'], isA<bool>());
      expect(body['liveness_passed'], isTrue);
    });

    test('an embedding outside the bounds the server accepts is refused on-device', () {
      final tooShort = FaceCapture(
        nonce: 'a' * 64, embedding: List<double>.filled(32, 0.1), dims: 32,
        modelVersion: 'human-3', completedChallenges: const ['blink'],
      );
      expect(tooShort.isUsable, isFalse);
      final notFinite = FaceCapture(
        nonce: 'a' * 64, embedding: List<double>.filled(128, double.nan), dims: 128,
        modelVersion: 'human-3', completedChallenges: const ['blink'],
      );
      expect(notFinite.isUsable, isFalse);
    });

    test('toString never leaks the vector — an embedding is biometric data', () {
      final s = fakeCapture().toString();
      expect(s.contains('0.0078'), isFalse);
      expect(s, contains('human-3'));
    });

    test('every failure reason has a sentence the employee can act on', () {
      for (final reason in FaceFailure.values) {
        expect(faceFailureMessage(reason), isNotEmpty, reason: '$reason');
      }
      expect(faceFailureFromCode('camera_denied'), FaceFailure.cameraDenied);
      expect(faceFailureFromCode('timeout'), FaceFailure.timeout);
      // Anything unrecognised fails closed as an engine error, never as success.
      expect(faceFailureFromCode('something new'), FaceFailure.engineError);
    });
  });

  group('the punch flow', () {
    late FakeClockApi api;
    late FakeFixService fixes;
    late FakeFaceCapturer face;
    late TimeClockController c;

    setUp(() {
      api = FakeClockApi();
      fixes = FakeFixService();
      face = FakeFaceCapturer();
      c = TimeClockController(api: api, fixes: fixes);
    });

    test('the face check runs AFTER the fix and its result is submitted', () async {
      await c.load();
      await c.punch('in', capture: face.call);
      expect(fixes.acquired, 1);
      expect(face.calls, ['in']);
      final sent = api.punches.single;
      expect(sent['nonce'], 'a' * 64);
      expect(sent['completed_challenges'], ['blink', 'turn_head']);
      expect(sent['latitude'], 14.5515);
      expect(c.outcome, isA<PunchSuccess>());
    });

    test('a refused fix never reaches the camera', () async {
      // No point asking somebody to blink for twenty seconds and only then
      // telling them their location was rejected.
      await c.load();
      fixes.next = LocationFix(latitude: 1, longitude: 1, accuracyM: 5, isMocked: true, at: DateTime.now());
      await c.punch('in', capture: face.call);
      expect(face.calls, isEmpty);
      expect(api.punches, isEmpty);
    });

    test('cancelling the face check records nothing and leaves no error card', () async {
      await c.load();
      face.result = const FaceFailed(FaceFailure.cancelled);
      await c.punch('in', capture: face.call);
      expect(api.punches, isEmpty);
      // A cancel is a decision, not a failure — no red card is left behind.
      expect(c.outcome, isNull);
      expect(c.phase, ClockPhase.idle);
    });

    test('a failed face check is a failure with its own reason, and no punch', () async {
      await c.load();
      face.result = const FaceFailed(FaceFailure.noEmbedding);
      await c.punch('in', capture: face.call);
      expect(api.punches, isEmpty);
      expect(c.outcome, isA<PunchFailure>().having((o) => o.message, 'message', contains('better light')));
    });

    test("a server refusal carries the SERVER's words, not ours", () async {
      await c.load();
      face.result = const FaceFailed(
        FaceFailure.engineError,
        serverMessage: 'Your face is not enrolled yet, so the app cannot verify this punch.',
      );
      await c.punch('in', capture: face.call);
      expect(c.outcome, isA<PunchFailure>().having((o) => o.message, 'message', contains('not enrolled')));
    });

    test('a match failure from the server is surfaced, and today is unchanged', () async {
      await c.load();
      api.punchError = const ApiException(status: 422, message: 'Face not recognised. Please try again.');
      await c.punch('in', capture: face.call);
      expect(c.outcome, isA<PunchFailure>().having((o) => o.message, 'message', contains('not recognised')));
      expect(c.status!.canClockIn, isTrue);
    });

    test('a successful punch reports that it was face-verified', () async {
      await c.load();
      await c.punch('in', capture: face.call);
      final outcome = c.outcome as PunchSuccess;
      expect(outcome.response.faceVerified, isTrue);
      expect(outcome.response.matchDistance, 0.31);
    });
  });

  group('the screens', () {
    testWidgets('an unenrolled employee is told so instead of being shown the buttons', (tester) async {
      final api = FakeClockApi()..status_ = statusJson(faceEnrolled: false);
      await mount(tester, api, FakeFixService());
      expect(find.text('Face not enrolled yet'), findsOneWidget);
      expect(find.textContaining('Ask HR to enrol you'), findsOneWidget);
      // There is no way to punch from this screen at all.
      expect(find.text('Time In'), findsNothing);
      expect(find.text('Time Out'), findsNothing);
    });

    testWidgets('an enrolled employee gets the clock, and Time In runs the face check', (tester) async {
      final face = FakeFaceCapturer();
      final api = FakeClockApi();
      await mount(tester, api, FakeFixService(), face: face);
      expect(find.text('Time In'), findsOneWidget);
      await tester.tap(find.text('Time In'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(face.calls, ['in']);
      expect(api.punches.single['nonce'], 'a' * 64);
    });

    testWidgets('the capture screen hands its result back through the Navigator', (tester) async {
      // The WebView cannot run in a widget test, so the attempt itself is
      // stubbed; what is under test is that the screen RETURNS what it got.
      FaceResult? popped;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              popped = await Navigator.of(context).push<FaceResult>(MaterialPageRoute(
                builder: (_) => FaceCaptureScreen(
                  direction: 'in',
                  issueChallenge: (_) async => FaceChallenge(nonce: 'a' * 64, actions: const ['blink']),
                  debugRunner: () async => FaceCaptured(fakeCapture()),
                ),
              ));
            },
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(popped, isA<FaceCaptured>());
    });

    testWidgets('closing the capture screen is a cancel, never a punch', (tester) async {
      FaceResult? popped;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              popped = await Navigator.of(context).push<FaceResult>(MaterialPageRoute(
                builder: (_) => FaceCaptureScreen(
                  direction: 'in',
                  issueChallenge: (_) async => FaceChallenge(nonce: 'a' * 64, actions: const ['blink']),
                  // Never completes: the attempt is still running when the user
                  // hits the close button.
                  debugRunner: () => Completer<FaceResult>().future,
                ),
              ));
            },
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      // The waiting screen shows a spinner, which animates forever — so never
      // pumpAndSettle here; pump the route transition by hand.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(popped, isA<FaceFailed>().having((f) => f.reason, 'reason', FaceFailure.cancelled));
    });
  });

  group('the loopback asset server', () {
    late FaceAssetServer server;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      // flutter_test installs an HttpOverrides that mocks every HttpClient, so
      // a real request would be answered by the mock instead of our server.
      // These tests are ABOUT the real socket, so the override comes off.
      HttpOverrides.global = null;
      server = FaceAssetServer();
    });
    tearDown(() => server.stop());

    test('binds to loopback only and serves the capture page', () async {
      final base = await server.start();
      // Loopback, so the page is not reachable from the network — it only
      // exists to give the WebView a secure origin.
      expect(base, startsWith('http://127.0.0.1:'));

      final client = HttpClient();
      final res = await (await client.getUrl(Uri.parse('$base/capture.html'))).close();
      expect(res.statusCode, 200);
      final body = await res.transform(const Utf8Decoder()).join();
      // The page really is the capture surface, and it points at the bundled
      // weights rather than anything remote.
      expect(body, contains('hrisStart'));
      expect(body, contains("modelBasePath: 'models'"));
      client.close();
    });

    test('refuses anything outside the three asset paths', () async {
      final base = await server.start();
      final client = HttpClient();
      for (final path in ['/secrets.txt', '/pubspec.yaml', '/models/..%2F..%2Fpubspec.yaml']) {
        final res = await (await client.getUrl(Uri.parse('$base$path'))).close();
        expect(res.statusCode, 404, reason: path);
        await res.drain<void>();
      }
      client.close();
    });

    test('stop() releases the port', () async {
      final base = await server.start();
      await server.stop();
      expect(server.baseUrl, isNull);
      final client = HttpClient();
      await expectLater(
        client.getUrl(Uri.parse('$base/capture.html')).then((r) => r.close()),
        throwsA(isA<SocketException>()),
      );
      client.close();
    });
  });
}
