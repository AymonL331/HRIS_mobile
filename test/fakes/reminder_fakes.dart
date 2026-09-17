import 'package:hris_mobile/features/reminders/reminder_coordinator.dart';
import 'package:hris_mobile/features/reminders/reminder_models.dart';
import 'package:hris_mobile/features/reminders/reminder_notifier.dart';
import 'package:hris_mobile/features/reminders/reminder_scheduler.dart';
import 'package:hris_mobile/features/reminders/reminders_api.dart';
import 'package:hris_mobile/features/time_clock/clock_models.dart';

/// A stage on a day, as the schedule endpoint lists it. Manila is +08:00, so
/// `fires_at` is the wall-clock minus eight hours.
Map<String, dynamic> alarmJson({
  String kind = 'clock_in',
  int? slot = 1,
  String? type,
  String date = '2026-09-11',
  String time = '08:15',
  String tone = 'info',
  String title = 'Clock in for {date}',
  String message = 'No clock-in yet for **{date}**',
}) {
  final hh = int.parse(time.split(':')[0]);
  final mm = int.parse(time.split(':')[1]);
  final parts = date.split('-').map(int.parse).toList();
  final fires = DateTime.utc(parts[0], parts[1], parts[2], hh, mm).subtract(const Duration(hours: 8));
  return {
    'kind': kind,
    'slot': slot,
    'type': type ?? 'missing_clock_${kind == 'clock_in' ? 'in' : 'out'}_${slot ?? 'soft'}',
    'date': date,
    'trigger_time': time,
    'fires_at': fires.toIso8601String(),
    'label': 'Stage',
    'tone': tone,
    'title': title.replaceAll('{date}', date),
    'message': message.replaceAll('{date}', date),
  };
}

Map<String, dynamic> scheduleJson({
  bool enabled = true,
  String localDate = '2026-09-11',
  bool workingToday = true,
  bool workingTomorrow = true,
  List<Map<String, dynamic>>? alarms,
}) =>
    {
      'enabled': enabled,
      'timezone': 'Asia/Manila',
      'resolved_from': 'company',
      'server_time': '2026-09-10T22:00:00.000Z',
      'local_date': localDate,
      'working_day': {'today': workingToday, 'tomorrow': workingTomorrow},
      'alarms': alarms ??
          [
            alarmJson(),
            alarmJson(kind: 'clock_out', slot: 1, time: '18:00', tone: 'normal', title: 'Clock out {date}', message: 'Still in {date}'),
            alarmJson(kind: 'clock_out', slot: 2, time: '21:30', tone: 'urgent', title: 'Final {date}', message: 'Final {date}'),
            alarmJson(date: '2026-09-12'),
            alarmJson(kind: 'clock_out', slot: 1, date: '2026-09-12', time: '18:00', tone: 'normal'),
          ],
    };

Map<String, dynamic> notificationJson({
  int id = 1,
  String type = 'missing_clock_in_1',
  String? tone = 'info',
  String? date = '2026-09-11',
  String title = 'Clock in for 2026-09-11',
  String message = 'No clock-in yet for **2026-09-11**',
  String? readAt,
  String? ackDeadlineAt = '2026-09-11T01:00:00.000Z',
  String? acknowledgedAt,
  String createdAt = '2026-09-11T00:16:30.000Z',
}) =>
    {
      'id': id,
      'type': type,
      'title': title,
      'message': message,
      'data': {'tone': tone, 'date': date, 'stage': 'Stage'},
      'created_at': createdAt,
      'read_at': readAt,
      'ack_deadline_at': ackDeadlineAt,
      'acknowledged_at': acknowledgedAt,
      'disregarded_at': null,
    };

class FakeNotificationsApi implements NotificationsApi {
  List<Map<String, dynamic>> rows;
  Object? failNext;
  final calls = <String>[];

  FakeNotificationsApi([List<Map<String, dynamic>>? rows]) : rows = rows ?? [];

  void _maybeFail() {
    final f = failNext;
    if (f != null) {
      failNext = null;
      throw f;
    }
  }

  List<AppNotification> get _all => rows.map(AppNotification.fromJson).toList();

  @override
  Future<NotificationPage> list({bool unreadOnly = false, int limit = 10}) async {
    calls.add('list${unreadOnly ? ':unread' : ''}');
    _maybeFail();
    final items = _all.where((n) => !unreadOnly || !n.isRead).toList();
    return NotificationPage(items: items.take(limit).toList(), total: items.length);
  }

  @override
  Future<int> unreadCount() async {
    calls.add('count');
    _maybeFail();
    return _all.where((n) => !n.isRead).length;
  }

  Map<String, dynamic> _row(int id) => rows.firstWhere((r) => r['id'] == id);

  @override
  Future<void> markRead(int id) async {
    calls.add('read:$id');
    _maybeFail();
    _row(id)['read_at'] = '2026-09-11T00:20:00.000Z';
  }

  @override
  Future<void> markAllRead() async {
    calls.add('read-all');
    _maybeFail();
    for (final r in rows) {
      r['read_at'] ??= '2026-09-11T00:20:00.000Z';
    }
  }

  @override
  Future<AppNotification> acknowledge(int id) async {
    calls.add('ack:$id');
    _maybeFail();
    final r = _row(id);
    r['acknowledged_at'] = '2026-09-11T00:21:00.000Z';
    r['read_at'] ??= '2026-09-11T00:21:00.000Z';
    return AppNotification.fromJson(r);
  }

  @override
  Future<void> remove(int id) async {
    calls.add('remove:$id');
    _maybeFail();
    rows.removeWhere((r) => r['id'] == id);
  }
}

class FakeReminderScheduleApi implements ReminderScheduleApi {
  Map<String, dynamic> json;
  Object? error;
  int calls = 0;

  FakeReminderScheduleApi([Map<String, dynamic>? json]) : json = json ?? scheduleJson();

  @override
  Future<ReminderSchedule> schedule() async {
    calls++;
    if (error != null) throw error!;
    return ReminderSchedule.fromJson(json);
  }
}

/// Records what was shown; dedupes by key like the real one.
class FakeReminderNotifier implements ReminderNotifier {
  final shown = <String>[];

  @override
  Future<bool> showIfNew(AppNotification n) async {
    final key = 'srv:${n.id}';
    if (shown.contains(key)) return false;
    shown.add(key);
    return true;
  }

  @override
  Future<bool> showLocalFallback(ReminderAlarm a) async {
    final key = 'local:${a.type}:${a.date}';
    if (shown.contains(key)) return false;
    shown.add(key);
    return true;
  }
}

class FakeAlarmPort implements AlarmPort {
  final scheduled = <int, ({DateTime at, Map<String, dynamic> params})>{};
  final cancelled = <int>[];

  @override
  Future<bool> schedule({required int id, required DateTime at, required Map<String, dynamic> params}) async {
    scheduled[id] = (at: at, params: params);
    return true;
  }

  @override
  Future<bool> cancel(int id) async {
    cancelled.add(id);
    scheduled.remove(id);
    return true;
  }
}

class FakeReminderSync implements ReminderSync {
  final statuses = <ClockStatus>[];

  @override
  Future<void> onStatus(ClockStatus status) async => statuses.add(status);
}
