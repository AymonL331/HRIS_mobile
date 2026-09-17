import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/http/api_exception.dart';
import 'package:hris_mobile/features/reminders/notifications_controller.dart';

import '../fakes/reminder_fakes.dart';

void main() {
  late FakeNotificationsApi api;
  late FakeReminderNotifier notifier;
  late NotificationsController c;

  setUp(() {
    api = FakeNotificationsApi([
      notificationJson(id: 3, type: 'missing_clock_out_1', readAt: null),
      notificationJson(id: 2, readAt: '2026-09-11T00:18:00.000Z'),
      notificationJson(id: 1, readAt: null),
    ]);
    notifier = FakeReminderNotifier();
    c = NotificationsController(api: api, notifier: notifier, pollInterval: Duration.zero, observeLifecycle: false);
  });

  test('load fills the list and the badge, and announces NOTHING (a baseline)', () async {
    await c.load();
    expect(c.items.map((n) => n.id), [3, 2, 1]);
    expect(c.unreadCount, 2);
    expect(notifier.shown, isEmpty);
    expect(c.loading, isFalse);
  });

  test('a poll announces only UNREAD rows never seen before, once', () async {
    await c.load();
    api.rows.insert(0, notificationJson(id: 4, readAt: null));
    api.rows.insert(0, notificationJson(id: 5, readAt: '2026-09-11T00:30:00.000Z'));
    await c.poll();
    expect(notifier.shown, ['srv:4']);
    expect(c.unreadCount, 3);
    await c.poll();
    expect(notifier.shown, ['srv:4'], reason: 'seen — never twice');
  });

  test('a poll failure keeps the last good list', () async {
    await c.load();
    api.failNext = const ApiException.network('offline');
    await c.poll();
    expect(c.items.length, 3);
    expect(c.error, isNull);
  });

  test('a load failure reports the message', () async {
    api.failNext = const ApiException(status: 500, message: 'Boom');
    await c.load();
    expect(c.error, 'Boom');
  });

  test('mark read is optimistic and drops the badge; a failure resyncs', () async {
    await c.load();
    await c.markRead(1);
    expect(c.items.firstWhere((n) => n.id == 1).isRead, isTrue);
    expect(c.unreadCount, 1);
    expect(api.calls.last, 'read:1');

    api.failNext = const ApiException(status: 500, message: 'x');
    await c.markRead(3);
    // The server never flipped it; the reload puts it back.
    expect(c.items.firstWhere((n) => n.id == 3).isRead, isFalse);
    expect(c.unreadCount, 1);
  });

  test('mark all read clears the badge; acknowledge implies read and keeps the server\'s row', () async {
    await c.load();
    await c.markAllRead();
    expect(c.unreadCount, 0);
    expect(c.items.every((n) => n.isRead), isTrue);

    c = NotificationsController(api: api, pollInterval: Duration.zero, observeLifecycle: false);
    api.rows[2]['read_at'] = null;
    await c.load();
    expect(c.unreadCount, 1);
    await c.acknowledge(1);
    final n = c.items.firstWhere((n) => n.id == 1);
    expect(n.acknowledgedAt, isNotNull);
    expect(n.isRead, isTrue);
    expect(c.unreadCount, 0);
    expect(api.calls.last, 'ack:1');
  });

  test('acknowledge failure resyncs and rethrows so the screen can say so', () async {
    await c.load();
    api.failNext = const ApiException(status: 500, message: 'x');
    await expectLater(c.acknowledge(1), throwsA(isA<ApiException>()));
    expect(c.items.firstWhere((n) => n.id == 1).acknowledgedAt, isNull);
  });

  test('remove takes the row out at once and never re-announces it', () async {
    await c.load();
    await c.remove(3);
    expect(c.items.map((n) => n.id), [2, 1]);
    expect(c.unreadCount, 1);
    expect(api.calls.last, 'remove:3');
    await c.poll();
    expect(notifier.shown, isEmpty);
  });
}
