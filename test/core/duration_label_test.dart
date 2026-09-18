import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/time/duration_label.dart';

void main() {
  test('late / undertime / worked read in hours and minutes', () {
    expect(hoursMinutes(36), '36m');
    expect(hoursMinutes(60), '1h 00m');
    expect(hoursMinutes(81), '1h 21m');
    expect(hoursMinutes(143), '2h 23m');
    expect(hoursMinutes(480), '8h 00m');
    expect(hoursMinutes(0), '0m');
  });
}
