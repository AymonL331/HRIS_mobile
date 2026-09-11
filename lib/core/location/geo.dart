import 'dart:math' as math;

const _earthRadiusM = 6371000.0;

/// Great-circle distance in metres — the same formula the server's
/// `utils/geo.js` uses, so the range chip on the phone agrees with the flag
/// the server will record.
double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return 2 * _earthRadiusM * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}
