import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/session_controller.dart';
import '../../core/device/monotonic_clock.dart';
import '../../core/http/api_exception.dart';
import '../../core/http/endpoints.dart';
import '../../core/location/location_fix.dart';
import '../face/face_models.dart';
import 'offline_models.dart';

/// OFFLINE CLOCK-IN (2026-11-24, user: "offline clock in then it will just sync
/// when internet comes back ... for brownout purposes or no data").
///
/// With no signal the Time Clock still takes a fresh GPS fix and runs the face
/// check (liveness with actions the PHONE picks, since no server can). The face
/// code is matched right away against the employee's own enrolled face kept on
/// the phone ([OfflineKit]), so they know at once; the punch is kept here and
/// sent when the signal is back, and the server checks all of it again — the
/// face, the time (GPS time / running time), the place, the age. Anything that
/// does not check out goes to HR; nothing is silently dropped.

// ---- storage ------------------------------------------------------------------

abstract class OfflineStore {
  Future<OfflineKit?> readKit();
  Future<void> writeKit(OfflineKit? kit);
  Future<TimeAnchor?> readAnchor();
  Future<void> writeAnchor(TimeAnchor anchor);
  Future<Map<String, dynamic>?> readStatus();
  Future<void> writeStatus(Map<String, dynamic> status);
  Future<List<OfflinePunch>> readQueue();
  Future<void> add(OfflinePunch punch);
  Future<void> remove(String clientUuid);
  Future<List<OfflineSendResult>> readResults();
  Future<void> writeResults(List<OfflineSendResult> results);
}

/// The real store, per environment: the face pack in the keystore-encrypted
/// storage; each waiting punch as one file in the app's PRIVATE folder (no other
/// app can read it), deleted the moment the server has it; the anchor, the last
/// clock screen and the sent results in the app's preferences.
class DeviceOfflineStore implements OfflineStore {
  final String Function() envKey;
  final FlutterSecureStorage _secure;

  DeviceOfflineStore({required this.envKey, FlutterSecureStorage? secure})
      : _secure = secure ?? const FlutterSecureStorage();

  String _k(String name) => 'offline_clock.$name.${envKey()}';

  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/offline_punches/${envKey()}');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  @override
  Future<OfflineKit?> readKit() async {
    try {
      final raw = await _secure.read(key: _k('kit'));
      return raw == null ? null : OfflineKit.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeKit(OfflineKit? kit) async {
    if (kit == null) {
      await _secure.delete(key: _k('kit'));
    } else {
      await _secure.write(key: _k('kit'), value: jsonEncode(kit.toJson()));
    }
  }

  Future<Map<String, dynamic>?> _readPref(String name) async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_k(name));
      return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writePref(String name, Object value) async =>
      (await SharedPreferences.getInstance()).setString(_k(name), jsonEncode(value));

  @override
  Future<TimeAnchor?> readAnchor() async {
    final j = await _readPref('anchor');
    try {
      return j == null ? null : TimeAnchor.fromJson(j);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeAnchor(TimeAnchor anchor) => _writePref('anchor', anchor.toJson());

  @override
  Future<Map<String, dynamic>?> readStatus() => _readPref('status');

  @override
  Future<void> writeStatus(Map<String, dynamic> status) => _writePref('status', status);

  @override
  Future<List<OfflinePunch>> readQueue() async {
    final out = <OfflinePunch>[];
    try {
      final d = await _dir();
      await for (final f in d.list()) {
        if (f is! File || !f.path.endsWith('.json')) continue;
        try {
          out.add(OfflinePunch.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>));
        } catch (_) {
          // An unreadable file is left for a newer build rather than deleted.
        }
      }
    } catch (_) {}
    out.sort((a, b) => a.takenAt.compareTo(b.takenAt));
    return out;
  }

  @override
  Future<void> add(OfflinePunch punch) async {
    final d = await _dir();
    final f = File('${d.path}/${punch.clientUuid}.json');
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(punch.toJson()), flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<void> remove(String clientUuid) async {
    final f = File('${(await _dir()).path}/$clientUuid.json');
    if (await f.exists()) await f.delete();
  }

  @override
  Future<List<OfflineSendResult>> readResults() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_k('results'));
      if (raw == null) return const [];
      return (jsonDecode(raw) as List)
          .whereType<Map<String, dynamic>>()
          .map((j) => OfflineSendResult(
                clientUuid: j['client_uuid'] as String,
                direction: j['direction'] as String,
                takenAt: DateTime.parse(j['taken_at'] as String).toUtc(),
                status: j['status'] as String,
                message: (j['message'] ?? '') as String,
                reviewReason: j['review_reason'] as String?,
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> writeResults(List<OfflineSendResult> results) => (SharedPreferences.getInstance()).then((p) => p.setString(
        _k('results'),
        jsonEncode([
          for (final r in results)
            {
              'client_uuid': r.clientUuid,
              'direction': r.direction,
              'taken_at': r.takenAt.toIso8601String(),
              'status': r.status,
              'message': r.message,
              'review_reason': r.reviewReason,
            },
        ]),
      ));
}

/// Tests.
class MemoryOfflineStore implements OfflineStore {
  OfflineKit? kit;
  TimeAnchor? anchor;
  Map<String, dynamic>? status;
  final queue = <OfflinePunch>[];
  List<OfflineSendResult> results = [];

  @override
  Future<OfflineKit?> readKit() async => kit;
  @override
  Future<void> writeKit(OfflineKit? k) async => kit = k;
  @override
  Future<TimeAnchor?> readAnchor() async => anchor;
  @override
  Future<void> writeAnchor(TimeAnchor a) async => anchor = a;
  @override
  Future<Map<String, dynamic>?> readStatus() async => status;
  @override
  Future<void> writeStatus(Map<String, dynamic> s) async => status = s;
  @override
  Future<List<OfflinePunch>> readQueue() async => [...queue]..sort((a, b) => a.takenAt.compareTo(b.takenAt));
  @override
  Future<void> add(OfflinePunch p) async => queue.add(p);
  @override
  Future<void> remove(String id) async => queue.removeWhere((p) => p.clientUuid == id);
  @override
  Future<List<OfflineSendResult>> readResults() async => results;
  @override
  Future<void> writeResults(List<OfflineSendResult> r) async => results = [...r];
}

// ---- server -------------------------------------------------------------------

abstract class OfflineClockApi {
  Future<OfflineKit> kit();
  Future<Map<String, dynamic>> send(OfflinePunch punch);
}

class MobileOfflineClockApi implements OfflineClockApi {
  final SessionController session;
  const MobileOfflineClockApi(this.session);

  @override
  Future<OfflineKit> kit() => session.guard(() => session.client.get(
        Endpoints.offlineClockKit,
        parse: (d) => OfflineKit.fromServer(d as Map<String, dynamic>, DateTime.now().toUtc()),
      ));

  @override
  Future<Map<String, dynamic>> send(OfflinePunch punch) => session.guard(() => session.client.post(
        Endpoints.offlineClock,
        body: punch.toRequestJson(),
        parse: (d) => d as Map<String, dynamic>,
      ));
}

// ---- the service ----------------------------------------------------------------

class OfflineClockService extends ChangeNotifier {
  final OfflineStore store;
  final OfflineClockApi api;
  final MonotonicClock clock;
  final String? appVersion;
  final DateTime Function() _now;
  final math.Random _rng;

  OfflineClockService({
    required this.store,
    required this.api,
    this.clock = const PlatformMonotonicClock(),
    this.appVersion,
    DateTime Function()? now,
    math.Random? random,
  })  : _now = now ?? (() => DateTime.now().toUtc()),
        _rng = random ?? math.Random.secure();

  /// A fresh face pack is fetched at most this often (and whenever there is none).
  static const kitMaxAge = Duration(hours: 6);
  static const actions = ['blink', 'turn_head'];

  OfflineKit? _kit;
  List<OfflinePunch> _queue = const [];
  List<OfflineSendResult> _results = const [];
  bool _loaded = false;
  bool _syncing = false;

  OfflineKit? get kit => _kit;
  List<OfflinePunch> get pending => _queue;
  List<OfflineSendResult> get results => _results;
  bool get syncing => _syncing;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    _kit = await store.readKit();
    _queue = await store.readQueue();
    _results = await store.readResults();
    notifyListeners();
  }

  /// After every server reply carrying its time: remember it beside the phone's
  /// running clock.
  Future<void> onServerTime(DateTime serverUtc) async {
    final r = await clock.read();
    if (r == null) return;
    await store.writeAnchor(TimeAnchor(serverUtc: serverUtc.toUtc(), elapsedMs: r.elapsedMs, bootCount: r.bootCount));
  }

  /// The last clock screen the server sent, for opening the Time Clock offline.
  Future<void> cacheStatus(Map<String, dynamic> raw) => store.writeStatus(raw);
  Future<Map<String, dynamic>?> cachedStatus() => store.readStatus();

  /// Fetch the face pack when there is none, it is old, or the server's face
  /// model changed. Never throws: no pack only means no offline clock-in yet.
  Future<void> refreshKit({String? modelVersion, bool force = false}) async {
    await ensureLoaded();
    final k = _kit;
    final stale = k == null ||
        force ||
        _now().difference(k.fetchedAt) > kitMaxAge ||
        (modelVersion != null && modelVersion.isNotEmpty && k.modelVersion != modelVersion);
    if (!stale) return;
    try {
      final fresh = await api.kit();
      _kit = fresh.usable ? fresh : null;
      await store.writeKit(_kit);
      notifyListeners();
    } on ApiException {
      // keep the old pack until a fetch works
    }
  }

  /// The liveness challenge when no server can issue one: a random nonce and a
  /// random ORDERED subset of the actions, picked with a secure random source.
  FaceChallenge localChallenge() {
    final nonce = List.generate(32, (_) => _rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    final pool = [...actions]..shuffle(_rng);
    final take = 1 + _rng.nextInt(actions.length);
    return FaceChallenge(nonce: nonce, actions: pool.take(take).toList(growable: false));
  }

  String _uuid() {
    final b = List<int>.generate(16, (_) => _rng.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// Keep one punch. [phoneDistance] is the match the caller already made.
  Future<OfflinePunch> save({
    required String direction,
    required LocationFix fix,
    required FaceCapture capture,
    required double phoneDistance,
    bool noMatch = false,
    List<double> phoneTries = const [],
  }) async {
    await ensureLoaded();
    final nowUtc = _now();
    // WHEN, best first: server time + running time (the phone was not restarted
    // since), else the GPS time, else the phone's own clock. The server re-checks.
    DateTime? anchorAt;
    int? elapsedSince;
    final anchor = await store.readAnchor();
    final reading = await clock.read();
    if (anchor != null &&
        reading != null &&
        reading.elapsedMs >= anchor.elapsedMs &&
        (anchor.bootCount == null || reading.bootCount == null || anchor.bootCount == reading.bootCount)) {
      anchorAt = anchor.serverUtc;
      elapsedSince = reading.elapsedMs - anchor.elapsedMs;
    }
    final takenAt = anchorAt != null
        ? anchorAt.add(Duration(milliseconds: elapsedSince!))
        : (fix.gpsTime ?? nowUtc);
    final punch = OfflinePunch(
      clientUuid: _uuid(),
      direction: direction,
      takenAt: DateTime.fromMillisecondsSinceEpoch(takenAt.millisecondsSinceEpoch ~/ 1000 * 1000, isUtc: true),
      gpsTime: fix.gpsTime,
      anchorServerAt: anchorAt,
      elapsedSinceAnchorMs: elapsedSince,
      embedding: capture.embedding,
      completedChallenges: capture.completedChallenges,
      modelVersion: capture.modelVersion,
      phoneDistance: phoneDistance,
      latitude: fix.latitude,
      longitude: fix.longitude,
      accuracyM: fix.accuracyM,
      photoBase64: capture.hasPhoto ? capture.photoJpegBase64 : null,
      appVersion: appVersion,
      noMatch: noMatch,
      phoneTries: phoneTries,
    );
    await store.add(punch);
    _queue = await store.readQueue();
    notifyListeners();
    return punch;
  }

  /// Waiting punches for [localDate] in one direction.
  bool hasPending(String direction, String localDate) =>
      _queue.any((p) => p.direction == direction && p.localDate == localDate);

  /// Send every waiting punch, oldest first. Stops at the first sign the signal
  /// is still gone (or the server is down); a punch the server refuses outright
  /// is taken off the phone and reported. Returns how many the server took.
  Future<int> sync() async {
    await ensureLoaded();
    if (_syncing || _queue.isEmpty) return 0;
    _syncing = true;
    notifyListeners();
    var sent = 0;
    try {
      for (final p in [..._queue]) {
        try {
          final data = await api.send(p);
          await _record(OfflineSendResult.fromServer(p, data));
          sent++;
        } on ApiException catch (e) {
          final retryLater = e.isNetwork || e.status >= 500 || e.status == 429 || e.status == 408 || e.endsSession;
          if (retryLater) break;
          await _record(OfflineSendResult(
            clientUuid: p.clientUuid,
            direction: p.direction,
            takenAt: p.takenAt,
            status: 'refused',
            message: e.message,
          ));
        }
      }
    } finally {
      _syncing = false;
      notifyListeners();
    }
    return sent;
  }

  Future<void> _record(OfflineSendResult r) async {
    await store.remove(r.clientUuid);
    _queue = await store.readQueue();
    _results = [r, ..._results.where((x) => x.clientUuid != r.clientUuid)].take(10).toList();
    await store.writeResults(_results);
    notifyListeners();
  }

  Future<void> dismissResult(String clientUuid) async {
    _results = _results.where((r) => r.clientUuid != clientUuid).toList();
    await store.writeResults(_results);
    notifyListeners();
  }
}
