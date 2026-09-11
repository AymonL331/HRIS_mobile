import 'package:flutter/foundation.dart';

import '../../core/http/api_exception.dart';
import '../../core/time/manila_time.dart';
import 'attendance_api.dart';
import 'attendance_models.dart';

/// Month-at-a-time DTR: the current month first, "Load previous month" walks
/// backwards. One request per month (a month fits one page of 31).
class AttendanceController extends ChangeNotifier {
  final AttendanceApi api;
  final DateTime Function() nowUtc;

  final List<DtrMonth> _months = [];
  bool _loading = false;
  String? _error;
  bool _disposed = false;

  AttendanceController({required this.api, DateTime Function()? nowUtc})
      : nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  List<DtrMonth> get months => List.unmodifiable(_months);
  bool get loading => _loading;
  String? get error => _error;
  bool get isEmpty => _months.isEmpty;

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
    await _load(t.year, t.month);
  }

  Future<void> loadPrevious() async {
    if (_months.isEmpty) return loadCurrent();
    final last = _months.last;
    final prev = DateTime(last.year, last.month - 1);
    await _load(prev.year, prev.month);
  }

  Future<void> refresh() async {
    if (_months.isEmpty) return loadCurrent();
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
