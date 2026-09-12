import 'package:flutter/foundation.dart';

import '../../core/http/api_exception.dart';
import 'payslip_api.dart';
import 'payslip_breakdown_models.dart';
import 'payslip_models.dart';

/// How the detail screen stands: still loading, ready, not mine / gone, or
/// failed. Mirrors the web hook's `loadState` contract so the two surfaces
/// treat a 404 the same way — as "not found", never as an error.
enum PayslipLoadState { loading, ready, notFound, error }

/// One payslip: the record itself, and — separately — the working behind it.
///
/// The two are deliberately independent. A breakdown is SUPPORTING detail: if
/// it cannot be built, the payslip is still correct and must still render, so
/// its failure is swallowed and the section simply does not appear. That is the
/// website's rule, kept here.
class PayslipDetailController extends ChangeNotifier {
  final PayslipApi api;
  final int payslipId;

  Payslip? _payslip;
  PayslipBreakdown? _breakdown;
  PayslipLoadState _state = PayslipLoadState.loading;
  String? _error;
  bool _breakdownLoading = true;
  bool _disposed = false;

  PayslipDetailController({required this.api, required this.payslipId});

  Payslip? get payslip => _payslip;
  PayslipBreakdown? get breakdown => _breakdown;
  PayslipLoadState get state => _state;
  String? get error => _error;
  bool get breakdownLoading => _breakdownLoading;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    _state = PayslipLoadState.loading;
    _error = null;
    _notify();
    try {
      _payslip = await api.detail(payslipId);
      _state = PayslipLoadState.ready;
    } on ApiException catch (e) {
      _payslip = null;
      _state = e.status == 404 ? PayslipLoadState.notFound : PayslipLoadState.error;
      _error = e.message;
      _breakdownLoading = false;
      _notify();
      return;
    }
    _notify();
    await _loadBreakdown();
  }

  Future<void> _loadBreakdown() async {
    _breakdownLoading = true;
    _notify();
    try {
      _breakdown = await api.breakdown(payslipId);
    } catch (_) {
      // Fail QUIETLY — see the class doc. The payslip above is what was paid.
      _breakdown = null;
    } finally {
      _breakdownLoading = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
