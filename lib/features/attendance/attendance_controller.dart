import 'package:flutter/foundation.dart';

import '../../core/http/api_exception.dart';
import '../../core/time/manila_time.dart';
import 'attendance_api.dart';
import 'attendance_models.dart';

/// The web's reporting periods (client utils/periods.js), same keys and words.
enum SummaryPeriod {
  thisMonth('This month'),
  lastMonth('Last month'),
  last3Months('Last 3 months'),
  thisYear('This year'),
  all('All time');

  final String label;
  const SummaryPeriod(this.label);
}

/// Month-at-a-time DTR: the current month first, "Load previous month" walks
/// backwards. One request per month (a month fits one page of 31).
class AttendanceController extends ChangeNotifier {
  final AttendanceApi api;
  final DateTime Function() nowUtc;

  final List<DtrMonth> _months = [];
  bool _loading = false;
  String? _error;
  bool _disposed = false;

  // SUMMARY (the web's Summary view): loaded the first time it is opened, then
  // kept, so switching Records ⇄ Summary is instant.
  SummaryPeriod _period = SummaryPeriod.thisYear;
  AttendanceSummary? _summary;
  bool _summaryLoading = false;
  String? _summaryError;

  // MY CORRECTION REQUESTS (the web's table under the records).
  List<CorrectionRequest> _corrections = const [];

  AttendanceController({required this.api, DateTime Function()? nowUtc})
      : nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  List<DtrMonth> get months => List.unmodifiable(_months);
  bool get loading => _loading;
  String? get error => _error;
  bool get isEmpty => _months.isEmpty;

  SummaryPeriod get period => _period;
  AttendanceSummary? get summary => _summary;
  bool get summaryLoading => _summaryLoading;
  String? get summaryError => _summaryError;
  List<CorrectionRequest> get corrections => List.unmodifiable(_corrections);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// The tenant-local "today" — Manila, never the phone's zone.
  String get today {
    final m = ManilaTime.toManila(nowUtc());
    return '${m.year}-${m.month.toString().padLeft(2, '0')}-${m.day.toString().padLeft(2, '0')}';
  }

  Future<void> loadCurrent() async {
    _months.clear();
    final t = ManilaTime.toManila(nowUtc());
    await Future.wait([_load(t.year, t.month), loadCorrections()]);
  }

  /// The correction history is a companion to the record: a failure here never
  /// blanks the DTR, it just leaves the list as it was.
  Future<void> loadCorrections() async {
    try {
      _corrections = await api.corrections();
      _notify();
    } on ApiException {
      // Keep the last list; the DTR's own error banner covers a dead connection.
    }
  }

  /// `{date_from, date_to}` for [p], in Manila days — the web's periodRange.
  (String, String) rangeOf(SummaryPeriod p) {
    final m = ManilaTime.toManila(nowUtc());
    String d(DateTime x) => '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
    return switch (p) {
      SummaryPeriod.thisMonth => (d(DateTime(m.year, m.month, 1)), today),
      // Day 0 of this month = the last day of the previous one.
      SummaryPeriod.lastMonth => (d(DateTime(m.year, m.month - 1, 1)), d(DateTime(m.year, m.month, 0))),
      SummaryPeriod.last3Months => (d(DateTime(m.year, m.month - 2, 1)), today),
      SummaryPeriod.thisYear => (d(DateTime(m.year, 1, 1)), today),
      SummaryPeriod.all => ('', ''),
    };
  }

  Future<void> setPeriod(SummaryPeriod p) async {
    if (p == _period && _summary != null) return;
    _period = p;
    await loadSummary();
  }

  Future<void> loadSummary() async {
    _summaryLoading = true;
    _summaryError = null;
    _notify();
    final asked = _period;
    try {
      final (from, to) = rangeOf(asked);
      final res = await api.summary(dateFrom: from, dateTo: to);
      // A slower answer for a period the person has since left is dropped.
      if (asked == _period) _summary = res;
    } on ApiException catch (e) {
      if (asked == _period) _summaryError = e.message;
    } finally {
      if (asked == _period) _summaryLoading = false;
      _notify();
    }
  }

  Future<void> loadPrevious() async {
    if (_months.isEmpty) return loadCurrent();
    final last = _months.last;
    final prev = DateTime(last.year, last.month - 1);
    await _load(prev.year, prev.month);
  }

  Future<void> refresh() async {
    if (_months.isEmpty) return loadCurrent();
    await loadCorrections();
    final keep = _months.map((m) => (m.year, m.month)).toList();
    _months.clear();
    for (final (y, m) in keep) {
      await _load(y, m);
      if (_error != null) break;
    }
  }

  Future<void> _load(int year, int month) async {
    _loading = true;
    _error = null;
    _notify();
    try {
      final days = await api.month(year: year, month: month, upToDate: today);
      days.sort((a, b) => b.date.compareTo(a.date));
      _months.add(DtrMonth(year: year, month: month, days: days));
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _loading = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
