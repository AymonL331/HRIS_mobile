import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/features/time_clock/clock_models.dart';

void main() {
  test('flag reasons read in plain words; travel_order is named, never raw', () {
    expect(locationFlagLabel('low_accuracy'), 'Low GPS accuracy');
    expect(locationFlagLabel('out_of_geofence'), 'Outside worksite');
    expect(locationFlagLabel('travel_order'), 'Travel order');
    expect(locationFlagLabel('low_accuracy+travel_order'), 'Low GPS accuracy · travel order');
    expect(locationFlagLabel(null), 'see DTR');
  });

  test('status and punch read the travel-order fields; older servers default to false', () {
    expect(ClockStatus.fromJson({'travel_order_today': true}).travelOrderToday, isTrue);
    expect(ClockStatus.fromJson(const {}).travelOrderToday, isFalse);
    expect(ClockStatus.fromJson({'travel_order': {'to_number': 'TO-2026-0012'}}).travelOrderNumber, 'TO-2026-0012');
    expect(ClockStatus.fromJson(const {}).travelOrderNumber, isNull);
    expect(PunchResponse.fromJson({'direction': 'in', 'location': {'travel_order': true}}).travelOrder, isTrue);
    expect(PunchResponse.fromJson({'direction': 'in'}).travelOrder, isFalse);
  });
}
