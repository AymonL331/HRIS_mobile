import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/device/device_readiness_service.dart';
import '../../core/device/oem_hints.dart';

/// WILL THIS PHONE LEAVE HRIS RUNNING while the employee is clocked in?
///
/// One place for the question and the one tap that answers it, because two
/// surfaces ask it: the Time Clock warns when the answer is no (that is where
/// the recording happens), and Settings shows the state at all times (so any
/// phone can be checked without a problem having to appear first).
///
/// WHAT IT CAN AND CANNOT SEE. `ignoreBatteryOptimizations` is stock Android's
/// switch and the only one with an API. Xiaomi, OPPO/realme, vivo, Samsung,
/// HUAWEI and Infinix/TECNO each add their own (Autostart, "Allow background
/// activity", "Sleeping apps", "Force stop to save power" …) that no API
/// reports and no dialog can set — so for those brands the best the app can do
/// is NAME them, which is what `hint` carries. A phone can therefore read
/// "Allowed" here and still be killed by its manufacturer's cleaner; that is
/// the honest limit, and the hint is shown either way.
///
/// Unknown (the check failed, or no readiness service is provided — tests) is
/// treated as fine: a warning that might be wrong is worse than none.
class BackgroundRunningState {
  /// true = the phone will leave the app alone · false = it may stop it ·
  /// null = not known yet.
  final bool? unrestricted;

  /// false when nothing can be asked (no readiness service) — render nothing.
  final bool available;

  /// The system dialog is open / the check is running.
  final bool busy;

  /// Extra steps for this phone's brand, or null on stock Android.
  final OemHint? hint;

  /// Ask Android for the exemption (its own dialog), then re-check.
  final Future<void> Function() allow;

  /// Open this app's settings page, for the brand switches no dialog can set.
  final Future<void> Function() openSettings;

  const BackgroundRunningState({
    required this.unrestricted,
    required this.available,
    required this.busy,
    required this.hint,
    required this.allow,
    required this.openSettings,
  });
}

typedef BackgroundRunningBuilder = Widget Function(BuildContext context, BackgroundRunningState state);

/// Owns the check, the lifecycle re-check and the request; hands the state to a
/// builder so each surface decides how to show it.
class BackgroundRunning extends StatefulWidget {
  final BackgroundRunningBuilder builder;

  const BackgroundRunning({super.key, required this.builder});

  @override
  State<BackgroundRunning> createState() => _BackgroundRunningState();
}

class _BackgroundRunningState extends State<BackgroundRunning> with WidgetsBindingObserver {
  DeviceReadinessService? _service;
  bool? _unrestricted;
  OemHint? _hint;
  bool _busy = false;

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

  /// Re-checked on every return to the foreground: the employee usually comes
  /// back FROM the settings page they were just sent to, and the setting also
  /// drifts on its own (a battery-saver prompt, a system update, an OEM cleaner).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final s = _service;
    if (s == null) return;
    try {
      final r = await s.check();
      if (!mounted) return;
      setState(() {
        _unrestricted = r.batteryUnrestricted;
        _hint = oemBatteryHint(r.manufacturer);
      });
    } catch (_) {
      // Unknown stays unknown — see the class docblock.
    }
  }

  Future<void> _allow() async {
    final s = _service;
    if (s == null) return;
    setState(() => _busy = true);
    try {
      await s.requestBatteryExemption();
    } catch (_) {
      // The dialog failed to open; the re-check below decides what is shown.
    }
    if (mounted) setState(() => _busy = false);
    await _check();
  }

  Future<void> _openSettings() async {
    final s = _service;
    if (s == null) return;
    try {
      await s.openAppSettings();
    } catch (_) {
      // Nothing to recover: the re-check on resume reports the real state.
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(
      context,
      BackgroundRunningState(
        unrestricted: _unrestricted,
        available: _service != null,
        busy: _busy,
        hint: _hint,
        allow: _allow,
        openSettings: _openSettings,
      ),
    );
  }
}

/// The brand steps as a small bullet list, shown under whichever control the
/// reader is looking at. Wording is deliberately tentative ("names vary by
/// model") because these menus differ between versions of the same skin.
class OemHintLines extends StatelessWidget {
  final OemHint hint;
  final Color color;

  const OemHintLines({super.key, required this.hint, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'On ${hint.brand} phones, also do this ${hint.where} (names vary by model):',
          style: TextStyle(fontSize: 12, height: 1.45, fontWeight: FontWeight.w600, color: color),
        ),
        for (final step in hint.steps)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('• $step', style: TextStyle(fontSize: 12, height: 1.45, color: color)),
          ),
      ],
    );
  }
}
