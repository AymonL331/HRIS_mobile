import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/device/monotonic_clock.dart';
import 'package:hris_mobile/core/http/api_exception.dart';
import 'package:hris_mobile/core/location/location_fix.dart';
import 'package:hris_mobile/core/time/server_clock.dart';
import 'package:hris_mobile/features/face/face_capture_screen.dart';
import 'package:hris_mobile/features/face/face_models.dart';
import 'package:hris_mobile/features/offline_clock/offline_clock_service.dart';
import 'package:hris_mobile/features/offline_clock/offline_models.dart';
import 'package:hris_mobile/features/time_clock/time_clock_controller.dart';

import '../fakes/clock_fakes.dart';

/// The enrolled face the phone keeps, and captures near / far from it.
final enrolled = List<double>.generate(128, (i) => (i + 1) / 128);
List<double> near() => [for (var i = 0; i < enrolled.length; i++) enrolled[i] + (i == 0 ? 0.1 : 0)];
List<double> far() => [for (final v in enrolled) v + 1];

OfflineKit kit() => OfflineKit(
      templates: [enrolled],
      threshold: 0.6,
      modelVersion: 'human-3',
      maxHours: 48,
      fetchedAt: DateTime.now().toUtc(),
    );

class FakeMonotonic implements MonotonicClock {
  int elapsedMs = 1000;
  int? bootCount = 7;
  @override
  Future<MonotonicReading?> read() async => MonotonicReading(elapsedMs: elapsedMs, bootCount: bootCount);
}

class FakeOfflineApi implements OfflineClockApi {
  final sent = <OfflinePunch>[];
  Object? sendError;
  String status = 'accepted';
  int kits = 0;

  @override
  Future<OfflineKit> kit() async {
    kits++;
    return OfflineKit.fromServer({
      'templates': [enrolled],
      'match_threshold': 0.6,
      'model_version': 'human-3',
      'max_hours': 48,
    }, DateTime.now().toUtc());
  }

  @override
  Future<Map<String, dynamic>> send(OfflinePunch punch) async {
    if (sendError != null) throw sendError!;
    sent.add(punch);
    return {'status': status, 'message': 'ok', 'review_reason': status == 'review' ? 'The face did not match on the server.' : null};
  }
}

const noSignal = ApiException.network('No internet connection.');

void main() {
  late FakeClockApi api;
  late FakeFixService fixes;
  late MemoryOfflineStore store;
  late FakeOfflineApi offApi;
  late FakeMonotonic mono;
  late OfflineClockService offline;
  late TimeClockController c;

  setUp(() {
    api = FakeClockApi();
    fixes = FakeFixService();
    store = MemoryOfflineStore();
    offApi = FakeOfflineApi();
    mono = FakeMonotonic();
    offline = OfflineClockService(store: store, api: offApi, clock: mono, appVersion: '1.20.0+52', random: math.Random(1));
    // The server clock is set to the fake status's day, so "today" matches it.
    final clock = ServerClock()..sync(DateTime.parse('2026-09-11T00:12:33.000Z'));
    c = TimeClockController(api: api, fixes: fixes, clock: clock, offline: offline);
  });
  tearDown(() => c.dispose());

  // The face check as the real screen runs it: ask the controller for the
  // challenge (server's, or the phone's own with no signal), answer it.
  Future<FaceResult> capture(String direction, {List<double>? embedding}) async {
    final ch = await c.issueChallenge(direction);
    return FaceCaptured(FaceCapture(
      nonce: ch.nonce,
      embedding: embedding ?? near(),
      dims: 128,
      modelVersion: 'human-3',
      completedChallenges: ch.actions,
    ));
  }

  // Online once (the screen, the time anchor and the face pack are kept), then the signal goes.
  Future<void> goOffline() async {
    await c.load();
    await Future<void>.delayed(Duration.zero);
    await offline.refreshKit(force: true);
    api.statusError = noSignal;
    api.challengeError = noSignal;
    await c.load(silent: true);
  }

  test('the face pack: the nearest enrolled face, measured like the server', () {
    final k = kit();
    expect(k.bestDistance(enrolled), 0);
    expect(k.bestDistance(near()), closeTo(0.1, 1e-9));
    expect(k.bestDistance([1, 2, 3]), isNull); // another length: no comparison
  });

  test('a phone-picked challenge: a 64-hex nonce and 1-2 known actions in an order', () {
    for (var i = 0; i < 20; i++) {
      final ch = offline.localChallenge();
      expect(ch.isUsable, isTrue);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(ch.nonce), isTrue);
      expect(ch.actions.toSet().difference({'blink', 'turn_head'}), isEmpty);
      expect(ch.actions.toSet().length, ch.actions.length);
    }
  });

  test('online: the screen, the face pack and the server time are kept for later', () async {
    await c.load();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(c.offlineMode, isFalse);
    expect(store.status, isNotNull);
    expect(store.anchor!.elapsedMs, 1000);
    expect(store.kit, isNotNull);
    expect(offApi.kits, 1);
  });

  test('no signal: the last screen stays, Time In is kept on the phone after the phone matched the face', () async {
    await goOffline();
    expect(c.offlineMode, isTrue);
    expect(c.status, isNotNull);
    expect(c.canClockIn, isTrue);

    mono.elapsedMs = 61000; // a minute after the last server time
    await c.punch('in', capture: (d) => capture(d));

    expect(c.outcome, isA<PunchSavedOffline>());
    expect(api.punches, isEmpty); // nothing reached the live punch
    expect(store.queue, hasLength(1));
    final p = store.queue.single;
    expect(p.direction, 'in');
    // WHEN = last server time + the phone's running time since, not the phone's clock.
    expect(p.takenAt, DateTime.parse('2026-09-11T00:13:33.000Z'));
    expect(p.elapsedSinceAnchorMs, 60000);
    expect(p.phoneDistance, closeTo(0.1, 1e-9));
    expect(p.completedChallenges, isNotEmpty);
    expect(fixes.lastTimeLimit, const Duration(seconds: 45)); // GPS alone takes longer
    // The day now reads clocked in on the phone.
    expect(c.canClockIn, isFalse);
    expect(c.canClockOut, isTrue);
  });

  test('no signal + a face that does not match the phone\'s pack -> refused on the spot, nothing kept', () async {
    await goOffline();
    await c.punch('in', capture: (d) => capture(d, embedding: far()));
    expect(c.outcome, isA<PunchFailure>());
    expect((c.outcome as PunchFailure).message, contains('Face not recognized'));
    expect(store.queue, isEmpty);
  });

  test('3 failed face tries in a row -> "Save for HR to check" keeps the last one with every score', () async {
    await goOffline();
    await c.punch('in', capture: (d) => capture(d, embedding: far()));
    expect((c.outcome as PunchFailure).message, contains('Try 1 of 3'));
    expect((c.outcome as PunchFailure).message, isNot(contains('score'))); // real app: no score
    await c.punch('in', capture: (d) => capture(d, embedding: far()));
    expect((c.outcome as PunchFailure).message, contains('Try 2 of 3'));
    await c.punch('in', capture: (d) => capture(d, embedding: far()));
    final o = c.outcome as PunchOfflineNoMatch;
    expect(o.tries, hasLength(3));
    expect(o.direction, 'in');
    expect(store.queue, isEmpty); // nothing kept until the employee chooses

    await c.saveForHr();
    expect(c.outcome, isA<PunchSavedOffline>());
    final p = store.queue.single;
    expect(p.noMatch, isTrue);
    expect(p.phoneTries, hasLength(3));
    final body = p.toRequestJson();
    expect(body['phone_no_match'], isTrue);
    expect(body['phone_tries'], hasLength(3));
    // Survives a restart of the app (the stored copy).
    final again = OfflinePunch.fromJson(p.toJson());
    expect(again.noMatch, isTrue);
    expect(again.phoneTries, p.phoneTries);
  });

  test('a match after failed tries starts the count again; the test build shows the score', () async {
    c.dispose();
    final clock = ServerClock()..sync(DateTime.parse('2026-09-11T00:12:33.000Z'));
    c = TimeClockController(api: api, fixes: fixes, clock: clock, offline: offline, showFaceScore: true);
    await goOffline();
    await c.punch('in', capture: (d) => capture(d, embedding: far()));
    expect((c.outcome as PunchFailure).message, contains('(score '));
    expect((c.outcome as PunchFailure).message, contains('limit 0.60'));
    await c.punch('in', capture: (d) => capture(d, embedding: far()));
    await c.punch('in', capture: (d) => capture(d));
    expect(c.outcome, isA<PunchSavedOffline>());
    expect(store.queue.single.noMatch, isFalse);
    await c.punch('out', capture: (d) => capture(d, embedding: far()));
    expect((c.outcome as PunchFailure).message, contains('Try 1 of 3'));
  });

  test('no signal and no face pack yet -> told to open the app once with internet', () async {
    api.statusError = noSignal;
    api.challengeError = noSignal;
    store.status = statusJson();
    await c.load();
    expect(c.offlineMode, isTrue);
    await c.punch('in', capture: (d) => capture(d));
    expect(c.outcome, isA<PunchFailure>());
    expect((c.outcome as PunchFailure).message, contains('Open the app once with internet'));
    expect(fixes.acquired, 0); // said before the GPS wait
    expect(store.queue, isEmpty);
  });

  test('the signal drops after the face check -> the punch is kept offline, not lost', () async {
    await c.load();
    await Future<void>.delayed(Duration.zero);
    await offline.refreshKit(force: true);
    api.punchError = noSignal;
    await c.punch('in', capture: (d) => capture(d));
    expect(c.outcome, isA<PunchSavedOffline>());
    expect(store.queue, hasLength(1));
  });

  test('back online: what was kept is sent, oldest first, and the answer is shown', () async {
    await goOffline();
    await c.punch('in', capture: (d) => capture(d));
    expect(store.queue, hasLength(1));

    api.statusError = null;
    api.challengeError = null;
    await c.load(silent: true);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(c.offlineMode, isFalse);
    expect(offApi.sent, hasLength(1));
    expect(store.queue, isEmpty);
    expect(offline.results.single.status, 'accepted');
    expect(offline.results.single.sentence, startsWith('Your offline Time In of'));
  });

  test('sending: still no signal -> kept; refused outright -> taken off and reported', () async {
    await goOffline();
    await c.punch('in', capture: (d) => capture(d));

    offApi.sendError = noSignal;
    expect(await offline.sync(), 0);
    expect(store.queue, hasLength(1));

    offApi.sendError = const ApiException(status: 409, message: 'This face capture has already been used.');
    expect(await offline.sync(), 0);
    expect(store.queue, isEmpty);
    expect(offline.results.single.status, 'refused');
    expect(offline.results.single.sentence, contains('could not be sent'));
  });

  test('HR review: the answer says it is waiting for HR, with the reason', () async {
    await goOffline();
    await c.punch('in', capture: (d) => capture(d));
    offApi.status = 'review';
    await offline.sync();
    expect(offline.results.single.status, 'review');
    expect(offline.results.single.sentence, contains('waiting for HR'));
    expect(offline.results.single.sentence, contains('did not match'));
  });

  test('a restart in between: the running time is not used, the GPS time is', () async {
    await goOffline();
    mono.bootCount = 8; // another start of the phone
    fixes.next = LocationFix(
      latitude: 14.5515, longitude: 121.0177, accuracyM: 9, isMocked: false, at: DateTime.now(),
      gpsTime: DateTime.parse('2026-09-11T00:20:00.000Z'),
    );
    await c.punch('in', capture: (d) => capture(d));
    final p = store.queue.single;
    expect(p.elapsedSinceAnchorMs, isNull);
    expect(p.takenAt, DateTime.parse('2026-09-11T00:20:00.000Z'));
    expect(p.toRequestJson()['gps_time'], '2026-09-11T00:20:00.000Z');
  });

  test('the request carries no nonce and never prints the face code', () async {
    await goOffline();
    await c.punch('in', capture: (d) => capture(d));
    final p = store.queue.single;
    final body = p.toRequestJson();
    expect(body.containsKey('nonce'), isFalse);
    expect(body['liveness_passed'], isTrue);
    expect(body['location'], isA<Map>());
    expect(p.toString().contains('0.0'), isFalse);
    // Round trip through storage.
    final back = OfflinePunch.fromJson(p.toJson());
    expect(back.takenAt, p.takenAt);
    expect(back.embedding, p.embedding);
    expect(back.phoneDistance, p.phoneDistance);
  });
}
