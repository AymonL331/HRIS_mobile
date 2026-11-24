import 'package:intl/intl.dart';

import '../../core/time/manila_time.dart';

/// The website's `utils/format.js` date helpers, for the self-service pages
/// copied from the web (Home, My Profile, My Accountabilities).
///
/// DATE columns reach the client as plain 'YYYY-MM-DD' strings; DATETIME columns
/// as UTC ISO instants ('…Z', server config `timezone: 'Z'`) and are shown in
/// Manila time — the zone the website renders them in.
abstract final class WebFormat {
  static final _dateOnly = RegExp(r'^(\d{4})-(\d{2})-(\d{2})');
  static final _date = DateFormat('MMM d, yyyy');
  static final _dateTime = DateFormat('MMM d, yyyy, h:mm a');

  /// formatDateOnly: 'Oct 23, 2026'; empty → '—'.
  static String dateOnly(Object? value) {
    final s = value?.toString() ?? '';
    if (s.isEmpty) return '—';
    final m = _dateOnly.firstMatch(s);
    if (m == null) return s;
    return _date.format(DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)));
  }

  /// formatDate: a calendar date ('YYYY-MM-DD') as is, an instant in Manila
  /// time; empty → '' (DetailField then shows its em dash).
  static String date(Object? value) {
    final s = value?.toString() ?? '';
    if (s.isEmpty) return '';
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return dateOnly(s);
    final utc = ManilaTime.parseUtc(s);
    return utc == null ? s : _date.format(ManilaTime.toManila(utc));
  }

  /// formatDateTime: 'Nov 23, 2026, 3:05 PM' (Manila); empty → ''.
  static String dateTime(Object? value) {
    final s = value?.toString() ?? '';
    if (s.isEmpty) return '';
    final utc = ManilaTime.parseUtc(s);
    return utc == null ? s : _dateTime.format(ManilaTime.toManila(utc));
  }
}

/// A JSON value as display text: null → '', numbers without a trailing '.0'.
String webText(Object? v) {
  if (v == null) return '';
  if (v is double && v == v.roundToDouble()) return v.toInt().toString();
  return v.toString();
}

/// A JSON object as `Map<String, dynamic>`, whatever map type it arrived as.
Map<String, dynamic>? asJsonMap(Object? v) => v is Map ? v.map((k, val) => MapEntry('$k', val)) : null;
