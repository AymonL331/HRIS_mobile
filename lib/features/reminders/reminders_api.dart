import '../../core/auth/session_controller.dart';
import '../../core/http/api_client.dart';
import '../../core/http/endpoints.dart';
import 'reminder_models.dart';

/// My bell, narrowed to the clock-in / clock-out reminders (user decision
/// 2026-09-17: the phone shows nothing else). Abstract so the controller and
/// the screen are tested against a scripted fake.
abstract class NotificationsApi {
  Future<NotificationPage> list({bool unreadOnly = false, int limit = 10});
  Future<int> unreadCount();
  Future<void> markRead(int id);
  Future<void> markAllRead();

  /// The explicit "I've got this" — a compliance record on the server, kept
  /// apart from mark-read exactly as the website keeps it.
  Future<AppNotification> acknowledge(int id);
  Future<void> remove(int id);
}

/// The reminder ladder as alarm instants.
abstract class ReminderScheduleApi {
  Future<ReminderSchedule> schedule();
}

const _kinds = {'kinds': 'reminders'};

/// The request shapes over a bare [ApiClient]. The alarm callback runs with no
/// session object (no UI, its own isolate), so it builds a client from the
/// stored connection and uses these directly; the signed-in app wraps the same
/// calls in the session's guard below.
class ClientNotificationsApi implements NotificationsApi {
  final ApiClient client;

  const ClientNotificationsApi(this.client);

  @override
  Future<NotificationPage> list({bool unreadOnly = false, int limit = 10}) => client.get(
        Endpoints.notifications,
        query: {..._kinds, 'page': '1', 'limit': '$limit', if (unreadOnly) 'unread_only': '1'},
        parse: (d) => NotificationPage.fromJson((d as Map).cast<String, dynamic>()),
      );

  @override
  Future<int> unreadCount() => client.get(
        Endpoints.notificationsUnreadCount,
        query: _kinds,
        parse: (d) => ((d as Map)['count'] as num?)?.toInt() ?? 0,
      );

  @override
  Future<void> markRead(int id) => client.post(Endpoints.notificationRead(id));

  @override
  Future<void> markAllRead() => client.post(Endpoints.notificationsReadAll);

  @override
  Future<AppNotification> acknowledge(int id) => client.post(
        Endpoints.notificationAcknowledge(id),
        parse: (d) => AppNotification.fromJson((d as Map).cast<String, dynamic>()),
      );

  @override
  Future<void> remove(int id) => client.delete(Endpoints.notification(id));
}

class ClientReminderScheduleApi implements ReminderScheduleApi {
  final ApiClient client;

  const ClientReminderScheduleApi(this.client);

  @override
  Future<ReminderSchedule> schedule() => client.get(
        Endpoints.reminderSchedule,
        parse: (d) => ReminderSchedule.fromJson((d as Map).cast<String, dynamic>()),
      );
}

/// The signed-in app's calls, through the session's guard so an expired token
/// or a revoked switch signs the phone out in one place.
class MobileNotificationsApi implements NotificationsApi {
  final SessionController session;

  const MobileNotificationsApi(this.session);

  ClientNotificationsApi get _raw => ClientNotificationsApi(session.client);

  @override
  Future<NotificationPage> list({bool unreadOnly = false, int limit = 10}) =>
      session.guard(() => _raw.list(unreadOnly: unreadOnly, limit: limit));

  @override
  Future<int> unreadCount() => session.guard(() => _raw.unreadCount());

  @override
  Future<void> markRead(int id) => session.guard(() => _raw.markRead(id));

  @override
  Future<void> markAllRead() => session.guard(() => _raw.markAllRead());

  @override
  Future<AppNotification> acknowledge(int id) => session.guard(() => _raw.acknowledge(id));

  @override
  Future<void> remove(int id) => session.guard(() => _raw.remove(id));
}

class MobileReminderScheduleApi implements ReminderScheduleApi {
  final SessionController session;

  const MobileReminderScheduleApi(this.session);

  @override
  Future<ReminderSchedule> schedule() => session.guard(() => ClientReminderScheduleApi(session.client).schedule());
}
