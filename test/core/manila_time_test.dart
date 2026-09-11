import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/time/manila_time.dart';
import 'package:hris_mobile/core/time/server_clock.dart';

void main() {
  test('UTC instants render in Manila (+08:00)', () {
    final utc = DateTime.utc(2026, 9, 11, 0, 30);
    expect(ManilaTime.time(utc), '8:30 AM');
    expect(ManilaTime.dateTime(utc), 'Fri, 11 Sep 2026 · 8:30 AM');
    expect(ManilaTime.clock(DateTime.utc(2026, 9, 11, 17, 0)), 'Saturday, 12 September 2026'); // rolls the date
  });

  test('parseUtc: Z strings are UTC; bare strings are treated as UTC by house rule', () {
    expect(ManilaTime.parseUtc('2026-09-11T00:12:33.000Z'), DateTime.utc(2026, 9, 11, 0, 12, 33));
    expect(ManilaTime.parseUtc('2026-09-11 00:12:33'), DateTime.utc(2026, 9, 11, 0, 12, 33));
    expect(ManilaTime.parseUtc(null), isNull);
    expect(ManilaTime.parseUtc(''), isNull);
  });

  test('server-resolved calendar dates are shown as-is', () {
    expect(ManilaTime.longDate('2026-09-11'), 'Friday, 11 September 2026');
    expect(ManilaTime.shortDate('2026-09-11'), 'Fri, 11 Sep');
  });

  test('ServerClock carries the server offset forward', () {
    final clock = ServerClock();
    expect(clock.synced, isFalse);
    clock.sync(DateTime.now().toUtc().add(const Duration(minutes: 5)));
    final drift = clock.nowUtc().difference(DateTime.now().toUtc()).inSeconds;
    expect(drift, inInclusiveRange(299, 301));
    expect(clock.synced, isTrue);
  });
}
