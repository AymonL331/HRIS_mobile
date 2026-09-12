import 'package:flutter/foundation.dart';

import '../../core/http/api_exception.dart';
import 'payslip_api.dart';
import 'payslip_models.dart';

/// My Payslips, a page at a time. The website pages with Previous/Next; a phone
/// list appends instead, so "Load more" walks forward and the rows already read
/// stay on screen.
class PayslipsController extends ChangeNotifier {
  final PayslipApi api;
  final int pageSize;

  final List<PayslipSummary> _items = [];
  int _page = 0;
  int _totalPages = 1;
  int _total = 0;
  bool _loading = false;
  bool _loaded = false;
  String? _error;
  bool _disposed = false;

  PayslipsController({required this.api, this.pageSize = 20});

  List<PayslipSummary> get items => List.unmodifiable(_items);
  bool get loading => _loading;

  /// True once a load has SUCCEEDED. Distinct from "no items": an account with
  /// no payslips yet is loaded and empty, which is the empty state, not an error.
  bool get loaded => _loaded;
  String? get error => _error;
  int get total => _total;
  bool get hasMore => _page < _totalPages;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> loadFirst() async {
    _items.clear();
    _page = 0;
    _totalPages = 1;
    _loaded = false;
    await _load(1);
  }

  Future<void> loadMore() async {
    if (_loading || !hasMore) return;
    await _load(_page + 1);
  }

  /// Pull-to-refresh: back to page one, dropping anything already paged in.
  Future<void> refresh() => loadFirst();

  Future<void> _load(int page) async {
    _loading = true;
    _error = null;
    _notify();
    try {
      final result = await api.list(page: page, limit: pageSize);
      // Page 1 REPLACES; a later page appends. A refresh that lands while rows
      // are on screen must not double them.
      if (page == 1) _items.clear();
      _items.addAll(result.items);
      _page = result.page;
      _totalPages = result.totalPages;
      _total = result.total;
      _loaded = true;
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
