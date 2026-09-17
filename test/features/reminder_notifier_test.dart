import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/features/reminders/reminder_models.dart';
import 'package:hris_mobile/features/reminders/reminder_notifier.dart';
import 'package:hris_mobile/features/reminders/reminder_store.dart';

import '../fakes/reminder_fakes.dart';

/// The plugin has no platform under test, so `show` fails quietly; what is
/// under test is the ONE-SHOWING rule the two isolates share through the store.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryReminderStore store;
  late LocalReminderNotifier notifier;

  setUp(() {
    store = InMemoryReminderStore();
    notifier = LocalReminderNotifier(store: store, now: () => DateTime.utc(2026, 9, 11, 1));
  });

  test('a server row is shown once, however many times it is offered', () async {
    final n = AppNotification.fromJson(notificationJson(id: 5));
    expect(await notifier.showIfNew(n), isTrue);
    expect(await notifier.showIfNew(n), isFalse);
    expect(await store.shownKeys(), {'srv:5'});
  });

  test('the offline fallback shows once, and the server row for the same stage/day is then NOT shown again', () async {
    final a = ReminderAlarm.fromJson(alarmJson());
    expect(await notifier.showLocalFallback(a), isTrue);
    expect(await notifier.showLocalFallback(a), isFalse);
    final n = AppNotification.fromJson(notificationJson(id: 9, type: a.type, date: a.date));
    expect(await notifier.showIfNew(n), isFalse);
    expect(await store.shownKeys(), containsAll(['local:missing_clock_in_1:2026-09-11', 'srv:9']));
  });

  test('a server row for another day of the same stage is a different reminder', () async {
    await notifier.showLocalFallback(ReminderAlarm.fromJson(alarmJson()));
    final n = AppNotification.fromJson(notificationJson(id: 10, date: '2026-09-12'));
    expect(await notifier.showIfNew(n), isTrue);
  });

  test('shown keys are pruned by the date of the reminder, so the set stays small', () async {
    await notifier.showIfNew(AppNotification.fromJson(notificationJson(id: 1, date: '2026-09-01')));
    await notifier.showIfNew(AppNotification.fromJson(notificationJson(id: 2, date: '2026-09-11')));
    expect(await store.shownKeys(), {'srv:2'});
  });
}
