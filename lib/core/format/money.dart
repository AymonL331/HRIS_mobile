import 'package:intl/intl.dart';

/// Money, formatted exactly as the website formats it.
///
/// The web's `utils/format.js` runs every peso figure through
/// `Intl.NumberFormat('en-PH', { style: 'currency', currency: 'PHP' })` and
/// renders a nullish or non-numeric value as an em dash so columns stay even.
/// This is that function, so a payslip reads the same on the phone as it does
/// in the browser — down to the dash.
///
/// API money columns are `DECIMAL(15,2)` and reach the client as STRINGS, so
/// everything here coerces through [num] rather than assuming a number.
abstract final class Money {
  static final NumberFormat _peso = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 2);

  /// `12480.5` / `'12480.50'` → `₱12,480.50`; null or unparseable → `—`.
  static String format(Object? value) {
    final n = toNum(value);
    return n == null ? '—' : _peso.format(n);
  }

  /// A rate at its REAL precision, for a line that shows arithmetic.
  ///
  /// `hourly_rate` is deliberately unrounded on the server (695 ÷ 8 = 86.875);
  /// its own comment says rounding it would make the shown working fail to
  /// reproduce the shown total. Printed as ₱86.88 the reader computes
  /// 86.88 × 1.10 = 95.57 while the payslip says 95.56. So this keeps up to
  /// four decimals and trims the trailing zeros a whole rate would carry.
  static String exactRate(Object? value) {
    final n = toNum(value);
    if (n == null) return '—';
    var s = n.toDouble().toStringAsFixed(4);
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '');
      s = s.replaceFirst(RegExp(r'\.$'), '');
    }
    return '₱$s';
  }

  /// The shared coercion: a DECIMAL string, an int, a double — or null for
  /// anything that is not a finite number (including `''`, which the web
  /// treats as "no value" rather than zero).
  static num? toNum(Object? value) {
    if (value == null) return null;
    if (value is num) return value.isFinite ? value : null;
    final parsed = num.tryParse('$value');
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  /// The same coercion with a zero default, for arithmetic (totals, sums)
  /// rather than display.
  static num asNum(Object? value) => toNum(value) ?? 0;
}
