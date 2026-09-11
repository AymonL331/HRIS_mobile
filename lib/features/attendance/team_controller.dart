import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/http/api_exception.dart';
import '../../core/time/manila_time.dart';
import 'team_api.dart';
import 'team_models.dart';

/// The team DTR, one day at a time: today first, step back and forward (never
/// past today), filter by name or code, page through a big roster.
class TeamAttendanceController extends ChangeNotifier {
  static const searchDebounce = Duration(milliseconds: 350);

  final TeamAttendanceApi api;
  final DateTime Function() nowUtc;

  String _date;
  String _search = '';
  final List<TeamDay> _items = [];
  int _page = 1;
  int _totalPages = 1;
  int _total = 0;
  bool _loading = false;
  bool _loadingMore = false;
  bool _loadedOnce = false;
  String? _error;
  int _requestId = 0;
  Timer? _debounce;
  bool _disposed = false;

  TeamAttendanceController({required this.api, DateTime Function()? nowUtc})
      : nowUtc = nowUtc ?? (() => DateTime.now().toUtc()),
        _date = '' {
    _date = today;
  }

  String get date => _date;
  String get search => _search;
  List<TeamDay> get items => List.unmodifiable(_items);
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get loadedOnce => _loadedOnce;
  String? get error => _error;
  int get total => _total;
  bool get hasMore => _page < _totalPages;
  bool get isToday => _date == today;

  /// The tenant-local "today" — Manila, never the phone's zone.
  String get today => _fmt(ManilaTime.toManila(nowUtc()));

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  int count(String dayType) => _items.where((d) => d.dayType == dayType).length;
  int get presentCount => _items.where((d) => d.dayType == 'worked' && d.status != 'late').length;
  int get lateCount => _items.where((d) => d.dayType == 'worked' && d.status == 'late').length;
  int get outOfRangeCount => _items.where((d) => d.outOfRange).length;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() => _load(reset: true);

  Future<void> refresh() => _load(reset: true);

  Future<void> setDate(String yyyyMmDd) async {
    if (yyyyMmDd.compareTo(today) > 0) yyyyMmDd = today; // the DTR has no future
    if (yyyyMmDd == _date && _loadedOnce) return;
    _date = yyyyMmDd;
    await _load(reset: true);
  }

  Future<void> previousDay() {
    final d = DateTime.parse(_date);
    return setDate(_fmt(DateTime(d.year, d.month, d.day - 1)));
  }

  Future<void> nextDay() {
    if (isToday) return Future.value();
    final d = DateTime.parse(_date);
    return setDate(_fmt(DateTime(d.year, d.month, d.day + 1)));
  }

  Future<void> goToToday() => setDate(today);

  /// Debounced: typing does not fire a request per keystroke.
  void setSearch(String value) {
    _search = value;
    _debounce?.cancel();
    _debounce = Timer(searchDebounce, () => _load(reset: true));
    _notify();
  }

  Future<void> loadMore() async {
    if (_loading || _loadingMore || !hasMore) return;
    _loadingMore = true;
    _error = null;
    _notify();
    final id = ++_requestId;
    try {
      final next = await api.day(date: _date, search: _search, page: _page + 1);
      if (id != _requestId) return; // a newer request superseded this one
      _items.addAll(next.items);
      _page = next.page;
      _totalPages = next.totalPages;
      _total = next.total;
    } on ApiException catch (e) {
      if (id == _requestId) _error = e.message;
    } finally {
      if (id == _requestId) {
        _loadingMore = false;
        _notify();
      }
    }
  }

  Future<void> _load({required bool reset}) async {
    _debounce?.cancel();
    _loading = true;
    _error = null;
    _notify();
    final id = ++_requestId;
    try {
      final first = await api.day(date: _date, search: _search, page: 1);
      if (id != _requestId) return;
      _items
        ..clear()
        ..addAll(first.items);
      _page = first.page;
      _totalPages = first.totalPages;
      _total = first.total;
      _loadedOnce = true;
    } on ApiException catch (e) {
      if (id == _requestId) _error = e.message;
    } finally {
      if (id == _requestId) {
        _loading = false;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }
}
