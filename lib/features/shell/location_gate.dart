import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/session_controller.dart';
import '../../core/device/device_readiness_service.dart';
import '../../core/location/location_gate_service.dart';
import '../setup/setup_step.dart';
import '../setup/setup_wizard_screen.dart';

/// Wraps everything a signed-in user can see. Until the phone is set up —
/// location on, "Allow all the time", precise, and (unless deliberately
/// skipped) notifications and the battery exemption — the child is NOT built;
/// the setup wizard stands in its place, one step at a time.
///
/// NOTHING HERE PROMPTS ON ITS OWN (2026-09-14). The mount and every resume only
/// OBSERVE. A system dialog or Settings page appears only when the employee taps
/// the button under the explanation of what is about to appear. That is the fix
/// for the confusing first launch, and it also rules out the Settings loop:
/// returning from Settings is itself a resume, and a resume never prompts.
class LocationGate extends StatefulWidget {
  final Widget child;

  const LocationGate({super.key, required this.child});

  @override
  State<LocationGate> createState() => _LocationGateState();
}

class _LocationGateState extends State<LocationGate> with WidgetsBindingObserver {
  GateVerdict? _verdict; // null = first check in flight
  DeviceReadiness _device = DeviceReadiness.ready;
  Set<String> _skipped = const {};
  bool _refusedOnce = false;

  /// An earlier step the employee went Back to, to re-read. Null = showing the
  /// step the phone is actually on. Cleared whenever that real step changes.
  SetupStep? _reviewing;
  SetupStep? _currentStep;

  bool _refreshing = false;
  bool _refreshAgain = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  /// Re-reads everything. A refresh asked for while one is in flight is not
  /// dropped — it runs again afterwards, so the result of an action that
  /// finished mid-check is never lost to a stale answer.
  Future<void> _refresh() async {
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    final gate = context.read<LocationGateService>();
    final readiness = context.read<DeviceReadinessService>();
    try {
      do {
        _refreshAgain = false;
        final verdict = await gate.check();
        final device = await readiness.check();
        final skipped = await readiness.skippedSteps();
        if (!mounted) return;
        setState(() {
          _verdict = verdict;
          _device = device;
          _skipped = skipped;
          if (verdict != GateVerdict.permissionDenied) _refusedOnce = false;
          final step = nextSetupStep(location: verdict, device: device, skipped: skipped);
          if (step != _currentStep) {
            // Real progress (or a regression) ends any review in progress.
            _currentStep = step;
            _reviewing = null;
          }
        });
      } while (_refreshAgain);
    } finally {
      _refreshing = false;
    }
  }

  /// A deliberate user action, then a fresh look. Every request underneath is
  /// already timed out; a throw must still never strand the screen.
  Future<void> _act(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {}
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final verdict = _verdict;
    if (verdict == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final step = nextSetupStep(location: verdict, device: _device, skipped: _skipped);
    if (step == null) return widget.child;

    final gate = context.read<LocationGateService>();
    final readiness = context.read<DeviceReadinessService>();

    // Back never undoes anything — the step is decided by what the phone has
    // granted. It shows an earlier step again to re-read; Next walks forward.
    final review = _reviewing;
    final shown = review != null && review.index < step.index ? review : step;
    final reviewing = shown != step;
    final previous = shown.index > 0 ? SetupStep.values[shown.index - 1] : null;

    return SetupWizardScreen(
      step: shown,
      reviewing: reviewing,
      onBack: previous == null ? null : () => setState(() => _reviewing = previous),
      onForward: reviewing
          ? () => setState(() {
                final next = SetupStep.values[shown.index + 1];
                _reviewing = next.index >= step.index ? null : next;
              })
          : null,
      verdict: verdict,
      device: _device,
      refusedOnce: _refusedOnce,
      onOpenLocationSettings: () => _act(gate.openLocationSettings),
      onRequestForeground: () => _act(() async {
        final after = await gate.requestForeground();
        _refusedOnce = after == GateVerdict.permissionDenied;
      }),
      onRequestBackground: () => _act(gate.requestBackground),
      onRequestNotifications: () => _act(readiness.requestNotifications),
      onRequestBattery: () => _act(readiness.requestBatteryExemption),
      onOpenAppSettings: () => _act(readiness.openAppSettings),
      onCheckAgain: _refresh,
      onSkip: () => _act(() => readiness.skipStep(step.name)),
      onSignOut: () => context.read<SessionController>().logout(),
    );
  }
}
