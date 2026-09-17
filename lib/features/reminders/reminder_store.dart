import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'reminder_models.dart';

/// What the reminder machinery remembers between runs — and, crucially,
/// BETWEEN ISOLATES: the alarm callback runs in its own engine with no UI, and
/// the signed-in app must see what it did (which reminders it already showed)
/// and vice versa.
///
/// Abstract so the scheduler, the callback and the controller are unit-tested
/// against an in-memory store with no platform channel.
abstract class ReminderStore {
  /// Reminders already shown as a phone notification, as keys: `srv:<id>` for a
  /// server row, `local:<type>:<date>` for an offline fallback.
  Future<Set<String>> shownKeys();

  /// Remember [key] as shown on [date]; entries older than a few days are
  /// dropped so the set never grows unbounded.
  Future<void> markShown(String key, String date);

  /// The alarms currently armed with Android, so a re-plan can cancel the ones
  /// no longer wanted and Settings can say what is next.
  Future<List<ReminderAlarm>> armed();
  Future<void> saveArmed(List<ReminderAlarm> alarms);

  /// The last schedule the server gave, re-used when it cannot be reached.
  Future<ReminderSchedule?> schedule();
  Future<void> saveSchedule(ReminderSchedule schedule);
  Future<DateTime?> lastSyncAt();
  Future<void> saveLastSyncAt(DateTime at);

  Future<LastStatus?> lastStatus();
  Future<void> saveLastStatus(LastStatus status);

  Future<ReminderConnection?> connection();
  Future<void> saveConnection(ReminderConnection connection);

  /// Sign-out: forget everything, including the connection, so a fired alarm
  /// finds nothing to act on.
  Future<void> clear();
}

/// How many local days of shown-keys are kept. A reminder is about ONE day and
/// the server's own de-dup means it can only arrive once, so three is ample.
const shownKeysKeptDays = 3;

/// The real store, on `SharedPreferencesAsync` — the variant with NO in-memory
/// cache. The legacy `SharedPreferences` caches on first read per isolate, and
/// a cached copy in the app would keep announcing a reminder the alarm callback
/// had already shown.
class PrefsReminderStore implements ReminderStore {
  final SharedPreferencesAsync _prefs;

  PrefsReminderStore([SharedPreferencesAsync? prefs]) : _prefs = prefs ?? SharedPreferencesAsync();

  static const _shown = 'reminders.shown';
  static const _armed = 'reminders.armed';
  static const _schedule = 'reminders.schedule';
  static const _lastSync = 'reminders.last_sync_at';
  static const _lastStatus = 'reminders.last_status';
  static const _baseUrl = 'reminders.base_url';
  static const _envKey = 'reminders.env_key';
  static const _appVersion = 'reminders.app_version';
  static const _keys = [_shown, _armed, _schedule, _lastSync, _lastStatus, _baseUrl, _envKey, _appVersion];

  @override
  Future<Set<String>> shownKeys() async =>
      (await _prefs.getStringList(_shown) ?? const []).map(keyOfShownEntry).toSet();

  @override
  Future<void> markShown(String key, String date) async {
    final current = await _prefs.getStringList(_shown) ?? const <String>[];
    await _prefs.setStringList(_shown, pruneShownEntries([...current, shownEntry(key, date)], date));
  }

  @override
  Future<List<ReminderAlarm>> armed() async => (await _prefs.getStringList(_armed) ?? const [])
      .map((s) => ReminderAlarm.fromJson((jsonDecode(s) as Map).cast<String, dynamic>()))
      .toList(growable: false);

  @override
  Future<void> saveArmed(List<ReminderAlarm> alarms) =>
      _prefs.setStringList(_armed, alarms.map((a) => jsonEncode(a.toJson())).toList(growable: false));

  @override
  Future<ReminderSchedule?> schedule() async {
    final raw = await _prefs.getString(_schedule);
    if (raw == null) return null;
    try {
      return ReminderSchedule.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveSchedule(ReminderSchedule schedule) => _prefs.setString(_schedule, jsonEncode(schedule.toJson()));

  @override
  Future<DateTime?> lastSyncAt() async => DateTime.tryParse(await _prefs.getString(_lastSync) ?? '')?.toUtc();

  @override
  Future<void> saveLastSyncAt(DateTime at) => _prefs.setString(_lastSync, at.toUtc().toIso8601String());

  @override
  Future<LastStatus?> lastStatus() async {
    final raw = await _prefs.getString(_lastStatus);
    if (raw == null) return null;
    try {
      return LastStatus.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveLastStatus(LastStatus status) => _prefs.setString(_lastStatus, jsonEncode(status.toJson()));

  @override
  Future<ReminderConnection?> connection() async {
    final baseUrl = await _prefs.getString(_baseUrl);
    final envKey = await _prefs.getString(_envKey);
    if (baseUrl == null || envKey == null) return null;
    return ReminderConnection(
      baseUrl: baseUrl,
      envKey: envKey,
      appVersion: await _prefs.getString(_appVersion) ?? '0.0.0',
    );
  }

  @override
  Future<void> saveConnection(ReminderConnection c) async {
    await _prefs.setString(_baseUrl, c.baseUrl);
    await _prefs.setString(_envKey, c.envKey);
    await _prefs.setString(_appVersion, c.appVersion);
  }

  @override
  Future<void> clear() async {
    for (final k in _keys) {
      await _prefs.remove(k);
    }
  }
}

/// A shown entry is `<date>|<key>` so pruning needs no second structure.
String shownEntry(String key, String date) => '$date|$key';
String keyOfShownEntry(String entry) {
  final i = entry.indexOf('|');
  return i < 0 ? entry : entry.substring(i + 1);
}

/// Keep only entries from the last [shownKeysKeptDays] days before [today]
/// (ISO dates compare as strings). Duplicates collapse.
List<String> pruneShownEntries(List<String> entries, String today) {
  final parts = today.split('-').map(int.tryParse).toList();
  if (parts.length != 3 || parts.any((p) => p == null)) return entries.toSet().toList(growable: false);
  final floor = DateTime.utc(parts[0]!, parts[1]!, parts[2]!).subtract(const Duration(days: shownKeysKeptDays));
  final floorStr = '${floor.year.toString().padLeft(4, '0')}-${floor.month.toString().padLeft(2, '0')}-${floor.day.toString().padLeft(2, '0')}';
  final kept = <String>{};
  for (final e in entries) {
    final i = e.indexOf('|');
    final date = i < 0 ? '' : e.substring(0, i);
    if (date.compareTo(floorStr) >= 0) kept.add(e);
  }
  return kept.toList(growable: false);
}

/// Tests and previews.
class InMemoryReminderStore implements ReminderStore {
  List<String> shown = [];
  List<ReminderAlarm> armedAlarms = [];
  ReminderSchedule? stored;
  DateTime? syncedAt;
  LastStatus? status;
  ReminderConnection? conn;

  @override
  Future<Set<String>> shownKeys() async => shown.map(keyOfShownEntry).toSet();

  @override
  Future<void> markShown(String key, String date) async =>
      shown = pruneShownEntries([...shown, shownEntry(key, date)], date);

  @override
  Future<List<ReminderAlarm>> armed() async => List.unmodifiable(armedAlarms);

  @override
  Future<void> saveArmed(List<ReminderAlarm> alarms) async => armedAlarms = List.of(alarms);

  @override
  Future<ReminderSchedule?> schedule() async => stored;

  @override
  Future<void> saveSchedule(ReminderSchedule schedule) async => stored = schedule;

  @override
  Future<DateTime?> lastSyncAt() async => syncedAt;

  @override
  Future<void> saveLastSyncAt(DateTime at) async => syncedAt = at;

  @override
  Future<LastStatus?> lastStatus() async => status;

  @override
  Future<void> saveLastStatus(LastStatus s) async => status = s;

  @override
  Future<ReminderConnection?> connection() async => conn;

  @override
  Future<void> saveConnection(ReminderConnection c) async => conn = c;

  @override
  Future<void> clear() async {
    shown = [];
    armedAlarms = [];
    stored = null;
    syncedAt = null;
    status = null;
    conn = null;
  }
}
