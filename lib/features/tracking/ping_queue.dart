import 'package:sqflite/sqflite.dart';

import 'tracking_models.dart';

/// The offline queue between recording a point and the server acknowledging it.
///
/// Points are written here FIRST and deleted only after a 2xx, so no signal,
/// airplane mode, a server restart or the app being killed never loses a point —
/// the next upload sends it. Owned by the tracking service's isolate alone; the
/// UI never opens it, so there is exactly one writer.
abstract class PingQueue {
  Future<void> add(QueuedPing ping);

  /// The oldest queued points, oldest first.
  Future<List<QueuedPing>> oldest({required int limit});

  Future<void> remove(Iterable<String> uuids);

  /// Drop every queued point of one shift (the server says it can never take them).
  Future<void> removeShift(int attendanceLogId);

  /// Drop everything (consent withdrawn: nothing further may be stored).
  Future<void> clear();

  Future<int> count();

  Future<void> close();
}

class SqflitePingQueue implements PingQueue {
  final Database _db;

  SqflitePingQueue._(this._db);

  static const _table = 'pings';

  static Future<SqflitePingQueue> open({String fileName = 'tracking_queue.db'}) async {
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      '$dir/$fileName',
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE $_table (
            uuid TEXT PRIMARY KEY,
            attendance_log_id INTEGER NOT NULL,
            kind TEXT NOT NULL,
            captured_at TEXT NOT NULL,
            latitude REAL,
            longitude REAL,
            accuracy_m REAL,
            altitude_m REAL,
            speed_mps REAL,
            heading_deg REAL,
            is_mocked INTEGER NOT NULL DEFAULT 0,
            battery_pct INTEGER
          )''');
        await db.execute('CREATE INDEX ix_pings_captured ON $_table (captured_at)');
      },
    );
    return SqflitePingQueue._(db);
  }

  @override
  Future<void> add(QueuedPing ping) =>
      _db.insert(_table, ping.toRow(), conflictAlgorithm: ConflictAlgorithm.ignore);

  @override
  Future<List<QueuedPing>> oldest({required int limit}) async {
    final rows = await _db.query(_table, orderBy: 'captured_at ASC, uuid ASC', limit: limit);
    return rows.map(QueuedPing.fromRow).toList(growable: false);
  }

  @override
  Future<void> remove(Iterable<String> uuids) async {
    final ids = uuids.toList();
    if (ids.isEmpty) return;
    await _db.delete(_table, where: 'uuid IN (${List.filled(ids.length, '?').join(', ')})', whereArgs: ids);
  }

  @override
  Future<void> removeShift(int attendanceLogId) =>
      _db.delete(_table, where: 'attendance_log_id = ?', whereArgs: [attendanceLogId]);

  @override
  Future<void> clear() => _db.delete(_table);

  @override
  Future<int> count() async => Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM $_table')) ?? 0;

  @override
  Future<void> close() => _db.close();
}

/// Tests and previews.
class InMemoryPingQueue implements PingQueue {
  final List<QueuedPing> items = [];

  @override
  Future<void> add(QueuedPing ping) async {
    if (items.any((p) => p.uuid == ping.uuid)) return;
    items.add(ping);
  }

  @override
  Future<List<QueuedPing>> oldest({required int limit}) async {
    final sorted = [...items]..sort((a, b) => a.capturedAtUtc.compareTo(b.capturedAtUtc));
    return sorted.take(limit).toList(growable: false);
  }

  @override
  Future<void> remove(Iterable<String> uuids) async {
    final ids = uuids.toSet();
    items.removeWhere((p) => ids.contains(p.uuid));
  }

  @override
  Future<void> removeShift(int attendanceLogId) async => items.removeWhere((p) => p.attendanceLogId == attendanceLogId);

  @override
  Future<void> clear() async => items.clear();

  @override
  Future<int> count() async => items.length;

  @override
  Future<void> close() async {}
}
