import '../../core/time/manila_time.dart';
import '../time_clock/clock_models.dart';

int? _int(Object? v) => v == null ? null : (v is int ? v : int.tryParse('$v'));
String? _text(Object? v) {
  if (v is! String) return null;
  final s = v.trim();
  return s.isEmpty ? null : s;
}

/// The Manila calendar date ('YYYY-MM-DD') of a UTC instant — the date the
/// server's reminder ladder is keyed on.
String manilaDateOf(DateTime utc) {
  final m = ManilaTime.toManila(utc);
  return '${m.year.toString().padLeft(4, '0')}-${m.month.toString().padLeft(2, '0')}-${m.day.toString().padLeft(2, '0')}';
}

/// One stage of the reminder ladder on one day, as `GET /api/me/reminder-schedule`
/// lists it: WHEN the phone should wake up and ask, and what the stage says.
class ReminderAlarm {
  final String kind; // clock_in | clock_out
  final int? slot; // null for the built-in _soft / _final stages
  final String type; // the notification `type` the detection job writes
  final String date; // 'YYYY-MM-DD', the affected local day
  final String triggerTime; // 'HH:MM' local
  final DateTime firesAt; // UTC instant of that wall-clock
  final String label;
  final String tone;
  final String title;
  final String message;

  const ReminderAlarm({
    required this.kind,
    required this.slot,
    required this.type,
    required this.date,
    required this.triggerTime,
    required this.firesAt,
    required this.label,
    required this.tone,
    required this.title,
    required this.message,
  });

  bool get isClockIn => kind == 'clock_in';

  factory ReminderAlarm.fromJson(Map<String, dynamic> j) => ReminderAlarm(
        kind: (j['kind'] ?? 'clock_out') as String,
        slot: _int(j['slot']),
        type: (j['type'] ?? '') as String,
        date: (j['date'] ?? '') as String,
        triggerTime: (j['trigger_time'] ?? '') as String,
        firesAt: ManilaTime.parseUtc(j['fires_at'] as String?) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        label: (j['label'] ?? '') as String,
        tone: (j['tone'] ?? 'normal') as String,
        title: (j['title'] ?? '') as String,
        message: (j['message'] ?? '') as String,
      );

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'slot': slot,
        'type': type,
        'date': date,
        'trigger_time': triggerTime,
        'fires_at': firesAt.toUtc().toIso8601String(),
        'label': label,
        'tone': tone,
        'title': title,
        'message': message,
      };
}

/// `GET /api/me/reminder-schedule`.
class ReminderSchedule {
  final bool enabled;
  final String timezone;
  final String resolvedFrom;
  final DateTime serverTime;
  final String localDate;
  final bool workingToday;
  final bool workingTomorrow;
  final List<ReminderAlarm> alarms;

  const ReminderSchedule({
    required this.enabled,
    required this.timezone,
    required this.resolvedFrom,
    required this.serverTime,
    required this.localDate,
    required this.workingToday,
    required this.workingTomorrow,
    required this.alarms,
  });

  factory ReminderSchedule.fromJson(Map<String, dynamic> j) {
    final wd = (j['working_day'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ReminderSchedule(
      enabled: j['enabled'] == true,
      timezone: (j['timezone'] ?? 'Asia/Manila') as String,
      resolvedFrom: (j['resolved_from'] ?? '') as String,
      serverTime: ManilaTime.parseUtc(j['server_time'] as String?) ?? DateTime.now().toUtc(),
      localDate: (j['local_date'] ?? '') as String,
      workingToday: wd['today'] == true,
      workingTomorrow: wd['tomorrow'] == true,
      alarms: ((j['alarms'] as List?) ?? const [])
          .map((e) => ReminderAlarm.fromJson((e as Map).cast<String, dynamic>()))
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'timezone': timezone,
        'resolved_from': resolvedFrom,
        'server_time': serverTime.toUtc().toIso8601String(),
        'local_date': localDate,
        'working_day': {'today': workingToday, 'tomorrow': workingTomorrow},
        'alarms': alarms.map((a) => a.toJson()).toList(growable: false),
      };
}

/// One row of my bell, as `GET /api/me/notifications` returns it. Only the
/// fields the app acts on are kept; `data.tone` and `data.date` come from the
/// stage that fired the reminder.
class AppNotification {
  final int id;
  final String type;
  final String title;
  final String message;
  final String? tone;
  final String? date;
  final DateTime? createdAt;
  final DateTime? readAt;
  final DateTime? ackDeadlineAt;
  final DateTime? acknowledgedAt;
  final DateTime? disregardedAt;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    this.tone,
    this.date,
    this.createdAt,
    this.readAt,
    this.ackDeadlineAt,
    this.acknowledgedAt,
    this.disregardedAt,
  });

  bool get isRead => readAt != null;

  factory AppNotification.fromJson(Map<String, dynamic> j) {
    final data = (j['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    return AppNotification(
      id: _int(j['id']) ?? 0,
      type: (j['type'] ?? '') as String,
      title: (j['title'] ?? '') as String,
      message: (j['message'] ?? '') as String,
      tone: _text(data['tone']),
      date: _text(data['date']),
      createdAt: ManilaTime.parseUtc(j['created_at'] as String?),
      readAt: ManilaTime.parseUtc(j['read_at'] as String?),
      ackDeadlineAt: ManilaTime.parseUtc(j['ack_deadline_at'] as String?),
      acknowledgedAt: ManilaTime.parseUtc(j['acknowledged_at'] as String?),
      disregardedAt: ManilaTime.parseUtc(j['disregarded_at'] as String?),
    );
  }

  AppNotification copyWith({DateTime? readAt, DateTime? acknowledgedAt}) => AppNotification(
        id: id,
        type: type,
        title: title,
        message: message,
        tone: tone,
        date: date,
        createdAt: createdAt,
        readAt: readAt ?? this.readAt,
        ackDeadlineAt: ackDeadlineAt,
        acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
        disregardedAt: disregardedAt,
      );
}

class NotificationPage {
  final List<AppNotification> items;
  final int total;

  const NotificationPage({required this.items, required this.total});

  factory NotificationPage.fromJson(Map<String, dynamic> j) => NotificationPage(
        items: ((j['items'] as List?) ?? const [])
            .map((e) => AppNotification.fromJson((e as Map).cast<String, dynamic>()))
            .toList(growable: false),
        total: _int((j['pagination'] as Map?)?['total']) ?? 0,
      );
}

/// What the phone last knew about today's punches — the only thing it has to
/// go on when an alarm fires and the server cannot be reached.
class LastStatus {
  final String localDate;
  final DateTime? clockInAt;
  final DateTime? clockOutAt;

  const LastStatus({required this.localDate, this.clockInAt, this.clockOutAt});

  factory LastStatus.fromClock(ClockStatus s) =>
      LastStatus(localDate: s.localDate, clockInAt: s.today?.clockInAt, clockOutAt: s.today?.clockOutAt);

  factory LastStatus.fromJson(Map<String, dynamic> j) => LastStatus(
        localDate: (j['local_date'] ?? '') as String,
        clockInAt: ManilaTime.parseUtc(j['clock_in_at'] as String?),
        clockOutAt: ManilaTime.parseUtc(j['clock_out_at'] as String?),
      );

  Map<String, dynamic> toJson() => {
        'local_date': localDate,
        'clock_in_at': clockInAt?.toUtc().toIso8601String(),
        'clock_out_at': clockOutAt?.toUtc().toIso8601String(),
      };
}

/// How the alarm callback reaches the server with no UI alive: the server, the
/// environment whose token to read from secure storage, and the app version
/// for the User-Agent. Holds no secret — same shape as the tracking config.
class ReminderConnection {
  final String baseUrl;
  final String envKey;
  final String appVersion;

  const ReminderConnection({required this.baseUrl, required this.envKey, required this.appVersion});
}
