import 'package:intl/intl.dart';

/// Every timestamp the server sends is UTC; the company runs on Asia/Manila
/// (+08:00, no daylight saving). The phone's own zone is never trusted — it may
/// be wrong, and it is not what the DTR is graded in.
abstract final class ManilaTime {
  static const offset = Duration(hours: 8);

  /// UTC instant → a wall-clock DateTime carrying Manila fields.
  static DateTime toManila(DateTime utc) => utc.toUtc().add(offset);

  static DateTime? parseUtc(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    final d = DateTime.tryParse(iso);
    if (d == null) return null;
    // A bare "YYYY-MM-DD HH:MM:SS" (no zone) from the server is UTC by house rule.
    return d.isUtc ? d : DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second, d.millisecond);
  }

  static String time(DateTime utc) => DateFormat('h:mm a').format(toManila(utc));
  static String dateTime(DateTime utc) => DateFormat('EEE, d MMM yyyy · h:mm a').format(toManila(utc));
  static String clock(DateTime utc) => DateFormat('EEEE, d MMMM yyyy').format(toManila(utc));

  /// A calendar date string the server already resolved in the tenant zone.
  static String longDate(String yyyyMmDd) {
    final d = DateTime.tryParse(yyyyMmDd);
    return d == null ? yyyyMmDd : DateFormat('EEEE, d MMMM yyyy').format(d);
  }

  static String shortDate(String yyyyMmDd) {
    final d = DateTime.tryParse(yyyyMmDd);
    return d == null ? yyyyMmDd : DateFormat('EEE, d MMM').format(d);
  }

  static String monthLabel(int year, int month) => DateFormat('MMMM yyyy').format(DateTime(year, month));
}
