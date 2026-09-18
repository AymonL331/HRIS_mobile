import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/device/oem_hints.dart';

void main() {
  test('stock Android and Samsung get their menu path, and the search as a fallback', () {
    for (final m in ['Google', 'motorola', 'HMD Global']) {
      final h = oemExactAlarmHint(m);
      expect(h.steps.first, 'Settings › Apps › Special app access › Alarms & reminders.', reason: m);
      expect(h.steps.last, startsWith("Can't find it?"));
    }
    final s = oemExactAlarmHint('samsung');
    expect(s.brand, 'Samsung');
    expect(s.steps.first, contains('Special access › Alarms and reminders'));
  });

  test('skins whose menus move get only the Settings search — never a guessed path', () {
    for (final (m, brand) in [
      ('Xiaomi', 'Xiaomi / Redmi / POCO'),
      ('OPPO', 'OPPO / realme / OnePlus'),
      ('vivo', 'vivo'),
      ('HONOR', 'HUAWEI / HONOR'),
      ('INFINIX MOBILITY LIMITED', 'Infinix / TECNO / itel'),
    ]) {
      final h = oemExactAlarmHint(m);
      expect(h.brand, brand);
      expect(h.steps, hasLength(2));
      expect(h.steps.first, contains('type "alarms"'));
      expect(h.steps.any((x) => x.contains('›')), isFalse, reason: '$m must not get a menu path');
    }
  });

  test('an unknown or empty manufacturer still gets the search step', () {
    for (final m in ['', 'SomeBrand']) {
      final h = oemExactAlarmHint(m);
      expect(h.brand, 'this');
      expect(h.steps.first, contains('type "alarms"'));
    }
  });
}
