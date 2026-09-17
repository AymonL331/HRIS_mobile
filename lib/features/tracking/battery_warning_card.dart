import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/device/device_readiness_service.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/app_card.dart';

/// Warns, on the Time Clock, while Android's battery optimisation may stop the
/// tracking service — and offers the fix in one tap.
///
/// The setup wizard already asks for this once, but that step is skippable and
/// the setting can be switched back by the phone (a "battery saver" prompt, a
/// system update, an OEM cleaner). A trail from 2026-09-16 showed the service
/// killed and restarted SIX times in one shift on a phone that had not been
/// exempted, so the reminder now lives where the recording is, and re-checks
/// every time the app comes back to the foreground. Shows nothing while the
/// phone is exempt, while the check is still running, or when the readiness
/// service is not provided (tests that mount the screen bare).
class BatteryWarningCard extends StatefulWidget {
  const BatteryWarningCard({super.key});

  @override
  State<BatteryWarningCard> createState() => _BatteryWarningCardState();
}

class _BatteryWarningCardState extends State<BatteryWarningCard> with WidgetsBindingObserver {
  DeviceReadinessService? _service;
  bool? _unrestricted;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    try {
      _service = context.read<DeviceReadinessService>();
    } on ProviderNotFoundException {
      _service = null;
    }
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final s = _service;
    if (s == null) return;
    try {
      final r = await s.check();
      if (mounted) setState(() => _unrestricted = r.batteryUnrestricted);
    } catch (_) {
      // Unknown is treated as fine: a warning that might be wrong is worse than none.
    }
  }

  Future<void> _fix() async {
    final s = _service;
    if (s == null) return;
    setState(() => _requesting = true);
    try {
      await s.requestBatteryExemption();
    } catch (_) {
      // The system dialog failed to open; the re-check below decides what to show.
    }
    if (mounted) setState(() => _requesting = false);
    await _check();
  }

  @override
  Widget build(BuildContext context) {
    if (_unrestricted != false) return const SizedBox.shrink();
    final t = HrisTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: HrisSpace.s3),
      child: AppCard(
        padding: const EdgeInsets.all(HrisSpace.s4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.battery_alert_outlined, color: t.warning.text),
            const SizedBox(width: HrisSpace.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Battery saving may stop your location recording',
                    style: TextStyle(fontSize: HrisType.md, fontWeight: HrisType.semibold, height: 1.35, color: t.warning.text),
                  ),
                  const SizedBox(height: HrisSpace.s1),
                  Text(
                    'Your phone is allowed to stop HRIS in the background. When it does, your shift shows gaps you did not cause. Set HRIS to "Unrestricted" (no battery optimisation).',
                    style: TextStyle(fontSize: HrisType.xs, height: 1.45, color: t.muted),
                  ),
                  const SizedBox(height: HrisSpace.s2),
                  OutlinedButton.icon(
                    onPressed: _requesting ? null : _fix,
                    icon: const Icon(Icons.battery_saver),
                    label: Text(_requesting ? 'Opening settings…' : 'Allow in the background'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
