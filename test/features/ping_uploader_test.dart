import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/http/api_exception.dart';
import 'package:hris_mobile/features/tracking/ping_queue.dart';
import 'package:hris_mobile/features/tracking/ping_uploader.dart';
import 'package:hris_mobile/features/tracking/tracking_models.dart';

QueuedPing point(int shift, int minute, {String kind = 'ping', double? speed = 1.2}) => QueuedPing(
      uuid: newPingUuid(),
      attendanceLogId: shift,
      kind: kind,
      capturedAt: DateTime.utc(2026, 9, 14, 0, minute),
      latitude: kind == 'ping' ? 14.5995 : null,
      longitude: kind == 'ping' ? 120.9842 : null,
      accuracyM: kind == 'ping' ? 8 : null,
      speedMps: speed,
    );

/// A scripted server: answers each batch from [answer], records every body.
class ScriptedPoster {
  final bodies = <Map<String, dynamic>>[];
  Object? Function(Map<String, dynamic> body) answer = (_) => {'accepted': 1, 'rejected': 0, 'tracking_active': true};

  Future<Map<String, dynamic>> call(Map<String, dynamic> body) async {
    bodies.add(body);
    final a = answer(body);
    if (a is Exception) throw a;
    return a as Map<String, dynamic>;
  }
}

void main() {
  late InMemoryPingQueue queue;
  late ScriptedPoster server;
  late PingUploader uploader;

  setUp(() {
    queue = InMemoryPingQueue();
    server = ScriptedPoster();
    uploader = PingUploader(queue: queue, post: server.call, nowUtc: () => DateTime.utc(2026, 9, 14, 1));
  });

  test('a batch is deleted only after the server acknowledges it; tracking_active is reported per shift', () async {
    await queue.add(point(7, 1));
    await queue.add(point(7, 2));
    server.answer = (b) => {'accepted': 2, 'rejected': 0, 'tracking_active': true};
    final r = await uploader.flush();
    expect(r.sent, 2);
    expect(r.accepted, 2);
    expect(r.activeByShift, {7: true});
    expect(r.retryLater, isFalse);
    expect(await queue.count(), 0);
  });

  test('the body carries the shift, the phone clock, and the server contract per point', () async {
    await queue.add(point(7, 1, speed: -1)); // Android's "unknown speed"
    await uploader.flush();
    final body = server.bodies.single;
    expect(body['attendance_log_id'], 7);
    expect(body['device_now'], '2026-09-14T01:00:00.000Z');
    final p = (body['pings'] as List).single as Map<String, dynamic>;
    expect(p['captured_at'], '2026-09-14T00:01:00.000Z');
    expect(p['kind'], 'ping');
    expect(p['latitude'], 14.5995);
    expect(p['is_mocked'], false);
    expect(p.containsKey('speed_mps'), isFalse, reason: 'an unknown speed is omitted, not sent as -1');
  });

  test('one shift per batch, oldest first — yesterday closing does not read as today closing', () async {
    await queue.add(point(8, 30));
    await queue.add(point(7, 1)); // older shift
    server.answer = (b) => {'accepted': 1, 'rejected': 0, 'tracking_active': b['attendance_log_id'] == 8};
    final r = await uploader.flush();
    expect(server.bodies.map((b) => b['attendance_log_id']), [7, 8]);
    expect(r.activeByShift, {7: false, 8: true});
  });

  test('a long offline stretch goes up in batches of batchSize', () async {
    for (var i = 0; i < 250; i++) {
      await queue.add(point(7, i % 60));
    }
    await uploader.flush();
    expect(server.bodies.map((b) => (b['pings'] as List).length), [100, 100, 50]);
    expect(await queue.count(), 0);
  });

  test('no network, a server error or an ngrok page: keep everything and retry later', () async {
    await queue.add(point(7, 1));
    for (final e in [
      const ApiException.network('offline'),
      const ApiException(status: 502, message: 'bad gateway'),
      const ApiException(status: 200, code: 'INVALID_ENVELOPE', message: 'html'),
    ]) {
      server.answer = (_) => e;
      final r = await uploader.flush();
      expect(r.retryLater, isTrue, reason: '$e');
      expect(await queue.count(), 1, reason: '$e');
    }
  });

  test('a signed-out phone stops recording but KEEPS its points', () async {
    await queue.add(point(7, 1));
    server.answer = (_) => const ApiException(status: 401, message: 'expired');
    final r = await uploader.flush();
    expect(r.stop, UploadStop.sessionEnded);
    expect(await queue.count(), 1);

    server.answer = (_) => const ApiException(status: 403, code: 'MOBILE_ACCESS_DISABLED', message: 'off');
    expect((await uploader.flush()).stop, UploadStop.sessionEnded);
  });

  test('withdrawn consent stops recording and CLEARS the queue (nothing more may be stored)', () async {
    await queue.add(point(7, 1));
    await queue.add(point(8, 2));
    server.answer = (_) => const ApiException(status: 422, message: 'consent', fieldErrors: {'location_consent': 'grant it'});
    final r = await uploader.flush();
    expect(r.stop, UploadStop.consentWithdrawn);
    expect(await queue.count(), 0);
  });

  test('a shift that no longer exists (404) is dropped, and the next shift still goes', () async {
    await queue.add(point(7, 1));
    await queue.add(point(7, 2));
    await queue.add(point(8, 3));
    server.answer = (b) => b['attendance_log_id'] == 7
        ? const ApiException(status: 404, message: 'gone')
        : {'accepted': 1, 'rejected': 0, 'tracking_active': true};
    final r = await uploader.flush();
    expect(r.dropped, 2);
    expect(r.accepted, 1);
    expect(r.activeByShift[7], isFalse);
    expect(await queue.count(), 0);
  });

  test('a malformed batch (422) is let go, so one bad batch can never jam the queue', () async {
    await queue.add(point(7, 1));
    server.answer = (_) => const ApiException(status: 422, message: 'bad', fieldErrors: {'device_now': 'bad'});
    final r = await uploader.flush();
    expect(r.dropped, 1);
    expect(r.retryLater, isFalse);
    expect(await queue.count(), 0);
  });
}
