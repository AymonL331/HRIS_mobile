import 'package:intl/intl.dart';

import 'leave_calendar_models.dart';

/// Month-grid arithmetic — the web's utils/calendarMonth.js. Every date is a
/// LOCAL calendar day 'YYYY-MM-DD' (never through a UTC conversion, which would
/// shift a PH day by one).

String _pad(int n) => n.toString().padLeft(2, '0');

String toDateKey(DateTime d) => '${d.year}-${_pad(d.month)}-${_pad(d.day)}';

DateTime? fromDateKey(String key) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(key);
  if (m == null) return null;
  return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

class MonthRef {
  final int year;
  final int month; // 1-12

  const MonthRef(this.year, this.month);

  factory MonthRef.of([DateTime? date]) {
    final d = date ?? DateTime.now();
    return MonthRef(d.year, d.month);
  }

  MonthRef shift(int delta) {
    final d = DateTime(year, month + delta, 1);
    return MonthRef(d.year, d.month);
  }

  /// "November 2026".
  String get label => DateFormat('MMMM yyyy').format(DateTime(year, month, 1));

  @override
  bool operator ==(Object other) => other is MonthRef && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);
}

/// Sunday-first, as the calendars it is read beside in PH.
const weekdayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

class MonthCell {
  final String key;
  final int day;
  final bool inMonth;

  /// Only Sunday shades as a day off (company workweek Mon–Sat).
  final bool restDay;

  const MonthCell({required this.key, required this.day, required this.inMonth, required this.restDay});
}

/// Whole weeks: the month plus the adjacent days that share its first and last
/// week — real cells, so a leave across the boundary shows on the days it covers.
List<MonthCell> buildMonthGrid(MonthRef m) {
  final first = DateTime(m.year, m.month, 1);
  final start = DateTime(m.year, m.month, 1 - (first.weekday % 7));
  final last = DateTime(m.year, m.month + 1, 0);
  final end = DateTime(m.year, m.month + 1, 0 + (6 - last.weekday % 7));
  final cells = <MonthCell>[];
  var cursor = start;
  while (!cursor.isAfter(end)) {
    cells.add(MonthCell(
      key: toDateKey(cursor),
      day: cursor.day,
      inMonth: cursor.month == m.month,
      restDay: cursor.weekday == DateTime.sunday,
    ));
    cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
  }
  return cells;
}

/// The window the grid covers — what the calendar asks the API for.
({String from, String to}) gridRange(MonthRef m) {
  final cells = buildMonthGrid(m);
  return (from: cells.first.key, to: cells.last.key);
}

class DayEntries {
  final List<CalendarLeave> leaves = [];
  final List<CalendarHoliday> holidays = [];
}

/// A leave appears on EVERY day it covers, clipped to the grid.
Map<String, DayEntries> indexByDay(LeaveCalendarData data, String from, String to) {
  final byDay = <String, DayEntries>{};
  DayEntries bucket(String k) => byDay.putIfAbsent(k, DayEntries.new);
  for (final leave in data.leaves) {
    final start = leave.dateFrom.compareTo(from) < 0 ? from : leave.dateFrom;
    final stop = leave.dateTo.compareTo(to) > 0 ? to : leave.dateTo;
    var cursor = fromDateKey(start);
    final end = fromDateKey(stop);
    if (cursor == null || end == null) continue;
    while (!cursor!.isAfter(end)) {
      bucket(toDateKey(cursor)).leaves.add(leave);
      cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
    }
  }
  for (final h in data.holidays) {
    bucket(h.date).holidays.add(h);
  }
  return byDay;
}
