import 'package:flutter/material.dart';

import '../../core/http/api_exception.dart';
import '../../shared/tokens.dart';
import 'clock_models.dart';

/// WHY LATE / WHY EARLY (server migration 128, user 2026-11-23). After a late
/// Time In or an early Time Out the Time Clock asks why. The popup cannot be
/// closed (no tap outside, no back button) until the reason is sent: the punch
/// is already saved, this only collects the reason. Same words as the website.
const int kReasonMin = 3;
const int kReasonMax = 500;

String minutesLabel(int m) {
  final h = m ~/ 60;
  final r = m % 60;
  return h == 0 ? '${r}m' : '${h}h ${r}m';
}

String reasonTitle(String kind) => kind == 'late' ? 'You clocked in late' : 'You clocked out early';

String reasonLead(PendingReason p) => p.kind == 'late'
    ? 'You are ${minutesLabel(p.minutes)} late today. Please tell us why.'
    : 'You are leaving ${minutesLabel(p.minutes)} before the end of your shift. Please tell us why.';

String reasonLabel(String kind) => kind == 'late' ? 'Why are you late?' : 'Why are you leaving early?';

/// Shows the popup and completes once the reason is sent.
Future<void> showLateReasonDialog(
  BuildContext context, {
  required PendingReason pending,
  required Future<void> Function(String reason) onSend,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => LateReasonDialog(pending: pending, onSend: onSend),
  );
}

class LateReasonDialog extends StatefulWidget {
  final PendingReason pending;
  final Future<void> Function(String reason) onSend;

  const LateReasonDialog({super.key, required this.pending, required this.onSend});

  @override
  State<LateReasonDialog> createState() => _LateReasonDialogState();
}

class _LateReasonDialogState extends State<LateReasonDialog> {
  final _text = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String get _trimmed => _text.text.replaceAll(RegExp(r'\s+'), ' ').trim();

  Future<void> _send() async {
    if (_trimmed.length < kReasonMin) {
      setState(() => _error = 'Please type your reason.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSend(_trimmed);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.fieldErrors['reason'] ?? e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not send. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final p = widget.pending;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(reasonTitle(p.kind)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(reasonLead(p)),
              const SizedBox(height: 12),
              TextField(
                key: const Key('late_reason_field'),
                controller: _text,
                autofocus: true,
                minLines: 3,
                maxLines: 5,
                maxLength: kReasonMax,
                enabled: !_busy,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: reasonLabel(p.kind),
                  errorText: _error,
                  border: const OutlineInputBorder(),
                ),
              ),
              Text(
                'Your time is already saved. HR and your branch head will see this reason.',
                style: TextStyle(color: t.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            key: const Key('late_reason_send'),
            onPressed: _busy || _trimmed.length < kReasonMin ? null : _send,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Send reason'),
          ),
        ],
      ),
    );
  }
}
