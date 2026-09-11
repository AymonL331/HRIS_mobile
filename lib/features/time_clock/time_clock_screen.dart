import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/session_controller.dart';
import '../../core/time/manila_time.dart';
import '../../shared/widgets/message_banner.dart';
import '../consent/consent_screen.dart';
import 'clock_models.dart';
import 'time_clock_controller.dart';

/// The home tab. Server time ticking, today's punches, the worksite range, the
/// two big buttons, and the outcome of the last tap.
class TimeClockScreen extends StatefulWidget {
  const TimeClockScreen({super.key});

  @override
  State<TimeClockScreen> createState() => _TimeClockScreenState();
}

class _TimeClockScreenState extends State<TimeClockScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = context.read<TimeClockController>();
      if (c.status == null && !c.loading) c.load();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<TimeClockController>();
    final status = c.status;

    if (status == null && c.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (status == null) {
      return _LoadError(message: c.loadError ?? 'Could not load your time clock.', onRetry: c.load);
    }
    if (!status.consentGiven) {
      return ConsentScreen(saving: c.consentSaving, onAgree: c.grantConsent);
    }

    final tenant = context.read<SessionController>().tenant;
    final now = c.clock.nowUtc();

    return RefreshIndicator(
      onRefresh: () => c.load(silent: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (c.loadError != null) ...[
            MessageBanner.warning(c.loadError!, onClose: () => c.load(silent: true)),
            const SizedBox(height: 12),
          ],
          _Header(name: status.employeeName, code: status.employeeCode, tenantName: tenant?.name, nowUtc: now),
          const SizedBox(height: 16),
          _TodayCard(status: status),
          const SizedBox(height: 12),
          _WorksiteCard(controller: c),
          const SizedBox(height: 20),
          _PunchButtons(controller: c),
          if (c.outcome != null) ...[
            const SizedBox(height: 16),
            _OutcomeCard(outcome: c.outcome!, onDismiss: c.dismissOutcome, onConsent: c.grantConsent),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String name;
  final String code;
  final String? tenantName;
  final DateTime nowUtc;
  const _Header({required this.name, required this.code, required this.tenantName, required this.nowUtc});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name.isEmpty ? 'Employee' : name, style: text.titleLarge),
        Text([if (code.isNotEmpty) code, ?tenantName].join(' · '), style: text.bodyMedium),
        const SizedBox(height: 12),
        Text(ManilaTime.timeWithSeconds(nowUtc), style: text.displaySmall?.copyWith(fontWeight: FontWeight.w600)),
        Text(ManilaTime.clock(nowUtc), style: text.bodyLarge),
        Text('Server time (Manila)', style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline)),
      ],
    );
  }
}

class _TodayCard extends StatelessWidget {
  final ClockStatus status;
  const _TodayCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final t = status.today;
    final scheme = Theme.of(context).colorScheme;
    Widget stamp(String label, DateTime? at) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 2),
              Text(at == null ? '—' : ManilaTime.time(at),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(color: at == null ? scheme.outline : null)),
            ],
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Today', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text(ManilaTime.shortDate(status.localDate), style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
            const SizedBox(height: 12),
            Row(children: [stamp('Time in', t?.clockInAt), stamp('Time out', t?.clockOutAt)]),
            if (t?.status != null) ...[
              const SizedBox(height: 10),
              Chip(label: Text(_statusLabel(t!.status!)), visualDensity: VisualDensity.compact),
            ],
          ],
        ),
      ),
    );
  }

  static String _statusLabel(String s) => switch (s) {
        'present' => 'Present',
        'late' => 'Late',
        'absent' => 'Absent',
        'official_business' => 'Official business',
        _ => s,
      };
}

class _WorksiteCard extends StatelessWidget {
  final TimeClockController controller;
  const _WorksiteCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    final ws = controller.status!.worksite;
    final fix = controller.lastFix;
    final range = controller.range;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    String line;
    Color tone = scheme.onSurfaceVariant;
    if (!ws.configured) {
      line = 'No worksite configured for your branch — punches are not range-checked.';
    } else if (fix == null) {
      line = 'Allowed radius ${ws.radiusM} m around ${ws.branchName ?? 'the worksite'}.';
    } else if (range.within == true) {
      line = 'In range — ${range.distanceM} m from ${ws.branchName ?? 'the worksite'} (limit ${ws.radiusM} m).';
      tone = scheme.primary;
    } else {
      line = 'Out of range — ${range.distanceM} m from ${ws.branchName ?? 'the worksite'} (limit ${ws.radiusM} m).';
      tone = scheme.error;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Icon(ws.configured ? Icons.place_outlined : Icons.location_searching, color: tone),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line, style: text.bodyMedium?.copyWith(color: tone)),
                  if (fix != null)
                    Text(
                      'GPS ±${fix.accuracyM.round()} m · ${_age(fix.at)}',
                      style: text.bodySmall?.copyWith(color: scheme.outline),
                    ),
                ],
              ),
            ),
            if (ws.configured)
              IconButton(
                tooltip: 'Check my range',
                onPressed: controller.rangeChecking || controller.busy ? null : controller.checkRange,
                icon: controller.rangeChecking
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location),
              ),
          ],
        ),
      ),
    );
  }

  static String _age(DateTime at) {
    final s = DateTime.now().difference(at).inSeconds;
    if (s < 5) return 'just now';
    if (s < 60) return '${s}s ago';
    return '${s ~/ 60} min ago';
  }
}

class _PunchButtons extends StatelessWidget {
  final TimeClockController controller;
  const _PunchButtons({required this.controller});

  @override
  Widget build(BuildContext context) {
    final s = controller.status!;
    final busy = controller.busy;
    final phaseText = switch (controller.phase) {
      ClockPhase.locating => 'Getting your location…',
      ClockPhase.submitting => 'Recording…',
      ClockPhase.idle => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: !busy && s.canClockIn ? () => controller.punch('in') : null,
                icon: const Icon(Icons.login),
                label: const Text('Time In'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: !busy && s.canClockOut ? () => controller.punch('out') : null,
                icon: const Icon(Icons.logout),
                label: const Text('Time Out'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
              ),
            ),
          ],
        ),
        if (phaseText != null) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Text(phaseText, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ],
      ],
    );
  }
}

class _OutcomeCard extends StatelessWidget {
  final PunchOutcome outcome;
  final VoidCallback onDismiss;
  final VoidCallback onConsent;
  const _OutcomeCard({required this.outcome, required this.onDismiss, required this.onConsent});

  @override
  Widget build(BuildContext context) {
    switch (outcome) {
      case PunchSuccess(:final response, :final warnLowAccuracy):
        final at = response.stampedAt;
        final what = response.direction == 'in' ? 'Timed in' : 'Timed out';
        final parts = <String>[
          if (at != null) '$what at ${ManilaTime.time(at)}.',
          if (response.within == true && response.distanceM != null) 'In range (${response.distanceM} m from the worksite).',
          if (response.within == false && response.distanceM != null)
            'Out of range (${response.distanceM} m from the worksite) — this punch is flagged for HR.',
          if (response.flagged && response.within != false) 'Flagged for HR: ${response.flagReason ?? 'see DTR'}.',
          if (warnLowAccuracy) 'Your GPS reading was coarse, so the punch is flagged for review.',
        ];
        return MessageBanner.success(parts.join(' '), onClose: onDismiss);
      case PunchInfo(:final message):
        return MessageBanner.info(message, onClose: onDismiss);
      case PunchBlocked(:final message):
        return MessageBanner.error('$message Move closer to your worksite and try again.', onClose: onDismiss);
      case PunchFailure(:final message):
        return MessageBanner.error(message, onClose: onDismiss);
      case PunchNeedsConsent():
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const MessageBanner.warning('Your location consent is not on record yet.'),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: onConsent, child: const Text('Review and give consent')),
          ],
        );
    }
  }
}

class _LoadError extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _LoadError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MessageBanner.error(message),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: () => onRetry(), child: const Text('Try again')),
            ],
          ),
        ),
      );
}
