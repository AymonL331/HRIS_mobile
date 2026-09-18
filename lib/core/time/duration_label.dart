/// A span of minutes in hours and minutes, the way the attendance screens show
/// it: "36m" under an hour, "1h 21m", "8h 00m". One helper so the worked time
/// and the late / undertime chips on the same row never read differently.
String hoursMinutes(int minutes) {
  if (minutes <= 0) return '0m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return h > 0 ? '${h}h ${m.toString().padLeft(2, '0')}m' : '${m}m';
}
