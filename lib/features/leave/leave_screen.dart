import 'package:flutter/material.dart';

import '../../core/http/api_exception.dart';
import '../../shared/button_styles.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/kit.dart';
import '../../shared/widgets/message_banner.dart';
import '../../shared/widgets/status_badge.dart';
import '../payslips/payslip_models.dart' show formatDateOnly;
import 'leave_api.dart';
import 'leave_models.dart';
import 'leave_request_form_screen.dart';

/// MY LEAVE (2026-11-23) — the web My Leave on the phone (MyLeavePage.jsx):
/// balances, File leave, my requests (paged, newest first) and Cancel for a
/// pending or approved one. Same server calls, same words. The web's toasts are
/// the banner at the top here.
class MyLeaveScreen extends StatefulWidget {
  final LeaveApi api;

  /// Whether this page is the one showing. The shell keeps every page built, so
  /// it loads when first opened (and refreshes each time it is opened again).
  final bool active;

  const MyLeaveScreen({super.key, required this.api, this.active = true});

  @override
  State<MyLeaveScreen> createState() => _MyLeaveScreenState();
}

class _MyLeaveScreenState extends State<MyLeaveScreen> {
  int _page = 1;
  LeaveRequestPage? _requests;
  List<LeaveBalance> _balances = const [];
  List<LeaveType> _types = const [];
  bool _loading = false;
  String? _error;
  ({String text, bool error})? _flash;
  int _requestId = 0;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) _load();
  }

  @override
  void didUpdateWidget(MyLeaveScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _load();
  }

  /// useMyLeave's load: the three reads together, race-guarded so a reload after
  /// filing or cancelling can't be overtaken by an older one.
  Future<void> _load() async {
    _started = true;
    final id = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.api.listRequests(page: _page),
        widget.api.balances(),
        widget.api.types(),
      ]);
      if (!mounted || id != _requestId) return;
      setState(() {
        _requests = results[0] as LeaveRequestPage;
        _balances = results[1] as List<LeaveBalance>;
        _types = results[2] as List<LeaveType>;
      });
    } on ApiException catch (e) {
      if (mounted && id == _requestId) setState(() => _error = e.message);
    } finally {
      if (mounted && id == _requestId) setState(() => _loading = false);
    }
  }

  String _typeName(int id) {
    for (final t in _types) {
      if (t.id == id) return t.name;
    }
    return 'Leave type #$id';
  }

  void _goTo(int page) {
    setState(() => _page = page);
    _load();
  }

  Future<void> _file() async {
    final filed = await LeaveRequestFormScreen.open(context, api: widget.api, types: _types);
    if (filed == true && mounted) {
      setState(() => _flash = (text: 'Leave request submitted.', error: false));
      await _load();
    }
  }

  Future<void> _cancel(LeaveRequestRow r) async {
    final message = await showDialog<String>(
      context: context,
      builder: (_) => _CancelDialog(
        message:
            '${_typeName(r.leaveTypeId)}, ${formatDateOnly(r.dateFrom)} – ${formatDateOnly(r.dateTo)}. This can\'t be undone.',
        onConfirm: () => widget.api.cancel(r.id),
      ),
    );
    if (!mounted || message == null) return;
    if (message.isEmpty) {
      setState(() => _flash = (text: 'Leave request cancelled.', error: false));
      await _load();
    } else {
      setState(() => _flash = (text: message, error: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final page = _requests;
    final rows = page?.items ?? const <LeaveRequestRow>[];
    final initial = (!_started || _loading) && page == null;
    final totalPages = page?.totalPages ?? 0;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s2, HrisSpace.s4, HrisSpace.s6),
        children: [
          Text('File leave and track your requests.', style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.muted)),
          const SizedBox(height: HrisSpace.s3),
          if (_flash != null) ...[
            _flash!.error
                ? MessageBanner.error(_flash!.text, onClose: () => setState(() => _flash = null))
                : MessageBanner.success(_flash!.text, onClose: () => setState(() => _flash = null)),
            const SizedBox(height: HrisSpace.s3),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(onPressed: _file, child: const Text('File leave')),
          ),
          const SizedBox(height: HrisSpace.s4),
          if (_balances.isNotEmpty) ...[
            _BalanceStrip(balances: _balances, typeName: _typeName),
            const SizedBox(height: HrisSpace.s4),
          ],
          if (initial && _error == null)
            const LoadingBlock(semanticsLabel: 'Loading leave')
          else if (!_loading && _error != null)
            StatePanel(
              title: "Couldn't load your leave",
              message: _error,
              error: true,
              action: OutlinedButton(onPressed: _load, child: const Text('Try again')),
            )
          else if (!_loading && rows.isEmpty)
            const StatePanel(
              title: 'No leave requests yet',
              message: 'Use File leave above — your requests will appear here.',
            )
          else if (rows.isNotEmpty) ...[
            RuledList(
              children: [
                for (final r in rows)
                  RuledRow(
                    child: _RequestRow(row: r, typeName: _typeName(r.leaveTypeId), onCancel: () => _cancel(r)),
                  ),
              ],
            ),
            const SizedBox(height: HrisSpace.s4),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: HrisSpace.s3,
              runSpacing: HrisSpace.s2,
              children: [
                Text(
                  'Page ${page!.page} of ${totalPages == 0 ? 1 : totalPages} · ${page.total} total',
                  style: TextStyle(fontSize: HrisType.sm, color: t.muted),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton(
                      style: HrisButtonStyles.secondary(context, minHeight: 36),
                      onPressed: _page <= 1 || _loading ? null : () => _goTo(_page - 1 < 1 ? 1 : _page - 1),
                      child: const Text('Previous'),
                    ),
                    const SizedBox(width: HrisSpace.s2),
                    FilledButton(
                      style: HrisButtonStyles.secondary(context, minHeight: 36),
                      onPressed: _page >= totalPages || _loading
                          ? null
                          : () => _goTo(_page + 1 > totalPages ? totalPages : _page + 1),
                      child: const Text('Next'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The web's ruled figure strip: one panel, two columns on a phone, each cell
/// the type, the days left (24 semibold, tabular) and "days left · N used of M (year)".
class _BalanceStrip extends StatelessWidget {
  final List<LeaveBalance> balances;
  final String Function(int) typeName;

  const _BalanceStrip({required this.balances, required this.typeName});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    Widget cell(LeaveBalance b) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s4, vertical: HrisSpace.s3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(typeName(b.leaveTypeId),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: HrisType.xs, height: 16 / 12, color: t.text2)),
              const SizedBox(height: 2),
              Text(jsNumber(b.remaining),
                  style: TextStyle(
                    fontSize: HrisType.stat,
                    height: 32 / 24,
                    fontWeight: HrisType.semibold,
                    color: t.text,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
              const SizedBox(height: 2),
              Text('days left · ${jsNumber(b.used)} used of ${jsNumber(b.accrued)} (${b.year})',
                  style: TextStyle(fontSize: HrisType.xs, height: 16 / 12, color: t.muted)),
            ],
          ),
        );

    final rows = <Widget>[];
    for (var i = 0; i < balances.length; i += 2) {
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: cell(balances[i])),
            VerticalDivider(width: 1, thickness: 1, color: t.border),
            Expanded(child: i + 1 < balances.length ? cell(balances[i + 1]) : const SizedBox()),
          ],
        ),
      ));
    }
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(HrisRadius.panel),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: t.border),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// One request — the web table's Type · From · To · Days · Status · Cancel.
class _RequestRow extends StatelessWidget {
  final LeaveRequestRow row;
  final String typeName;
  final VoidCallback onCancel;

  const _RequestRow({required this.row, required this.typeName, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final meta = TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text2);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(typeName, style: TextStyle(fontSize: HrisType.md, fontWeight: HrisType.medium, color: t.text)),
              const SizedBox(height: 2),
              Text('From ${formatDateOnly(row.dateFrom)} · To ${formatDateOnly(row.dateTo)}', style: meta),
              Text('Days ${row.daysLabel}', style: meta),
            ],
          ),
        ),
        const SizedBox(width: HrisSpace.s3),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            StatusBadge(leaveStatusLabels[row.status] ?? row.status ?? '—', tone: leaveStatusTone(row.status)),
            const SizedBox(height: HrisSpace.s1),
            if (row.cancellable)
              TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(
                  foregroundColor: t.danger.text,
                  minimumSize: const Size(48, 36),
                  padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s2),
                  textStyle: const TextStyle(fontWeight: HrisType.semibold, fontSize: HrisType.sm),
                ),
                child: const Text('Cancel'),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: HrisSpace.s2),
                child: Text('—', style: meta),
              ),
          ],
        ),
      ],
    );
  }
}

/// The web ConfirmDialog (tone danger): "Cancel this leave request?", Keep it /
/// Cancel request with a spinner while it runs. Pops '' on success, the error
/// message on failure, null when kept.
class _CancelDialog extends StatefulWidget {
  final String message;
  final Future<void> Function() onConfirm;

  const _CancelDialog({required this.message, required this.onConfirm});

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  bool _busy = false;

  Future<void> _go() async {
    setState(() => _busy = true);
    try {
      await widget.onConfirm();
      if (mounted) Navigator.of(context).pop('');
    } on ApiException catch (e) {
      if (mounted) Navigator.of(context).pop(e.message.isEmpty ? 'Could not cancel the request.' : e.message);
    } catch (_) {
      if (mounted) Navigator.of(context).pop('Could not cancel the request.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Cancel this leave request?'),
        content: Text(widget.message),
        actions: [
          TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Keep it')),
          FilledButton(
            style: HrisButtonStyles.danger(context),
            onPressed: _busy ? null : _go,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Cancel request'),
          ),
        ],
      ),
    );
  }
}
