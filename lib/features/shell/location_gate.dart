import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/session_controller.dart';
import '../../core/location/location_gate_service.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/app_card.dart';

/// Wraps everything a signed-in user can see. Unless location is granted
/// "Allow all the time" with PRECISE accuracy, and the device's location service
/// is on, the child is NOT built — a full-screen explanation stands in its place
/// with the buttons that fix it. Re-checks when the app returns to the
/// foreground (the user coming back from Settings), on mount, and on Retry, so
/// the block clears itself the moment the phone is set up right.
///
/// Only the MOUNT and the RETRY may raise a permission dialog. The resume
/// re-check is deliberately passive: returning from Settings is itself a resume,
/// so a prompting resume-check would throw the user straight back out to
/// Settings in a loop.
class LocationGate extends StatefulWidget {
  final Widget child;

  const LocationGate({super.key, required this.child});

  @override
  State<LocationGate> createState() => _LocationGateState();
}

class _LocationGateState extends State<LocationGate> with WidgetsBindingObserver {
  GateVerdict? _verdict; // null = first check in flight
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The user just arrived — this one may ask.
    _check(interactive: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // PASSIVE on purpose — see the class docblock. Observe, never prompt.
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check({bool interactive = false}) async {
    if (_checking) return;
    _checking = true;
    try {
      final v = await context.read<LocationGateService>().check(interactive: interactive);
      if (mounted) setState(() => _verdict = v);
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _verdict;
    if (v == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (v.blocks) {
      // The retry buttons are a deliberate user action, so they may ask.
      return LocationBlockedScreen(verdict: v, onRetry: () => _check(interactive: true));
    }
    return widget.child;
  }
}

class LocationBlockedScreen extends StatelessWidget {
  final GateVerdict verdict;
  final Future<void> Function() onRetry;

  const LocationBlockedScreen({super.key, required this.verdict, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final service = context.read<LocationGateService>();
    final scheme = Theme.of(context).colorScheme;
    final (icon, title, body, primaryLabel, primaryAction) = switch (verdict) {
      GateVerdict.serviceOff => (
          Icons.location_off_outlined,
          'Turn on location',
          "This app records where you clock in and out, so it can't run while your phone's location is off.",
          'Open location settings',
          service.openLocationSettings,
        ),
      GateVerdict.permissionDenied => (
          Icons.location_disabled_outlined,
          'Allow location access',
          'HRIS cannot run without your location. Tap Try again and choose "Precise". Android will then ask a second time — HRIS needs "Allow all the time", not only while the app is open.',
          'Try again',
          onRetry,
        ),
      GateVerdict.permissionDeniedForever => (
          Icons.location_disabled_outlined,
          'Location access is blocked',
          'Location for HRIS is turned off in your phone settings. Open the app settings, tap Permissions › Location, choose "Allow all the time", and turn on "Use precise location".',
          'Open app settings',
          service.openAppSettings,
        ),
      // Foreground-only. Both switches live on the same Settings page, so this
      // names both and the employee makes ONE trip.
      GateVerdict.backgroundDenied => (
          Icons.my_location,
          'Set location to "Allow all the time"',
          'HRIS needs your location all the time, not only while the app is open. Open the app settings, tap Permissions › Location, choose "Allow all the time", and make sure "Use precise location" is on.',
          'Open app settings',
          service.openAppSettings,
        ),
      GateVerdict.reducedAccuracy => (
          Icons.gps_not_fixed,
          'Precise location is required',
          'Location is set to "Approximate", which is only good to a few kilometres and cannot show you were at your branch. In the app settings, under Permissions › Location, turn on "Use precise location".',
          'Open app settings',
          service.openAppSettings,
        ),
      GateVerdict.ok => (Icons.check, '', '', '', onRetry),
    };

    // The web's full-page block: one card on the page background, a danger
    // icon, the reason, the way out.
    final t = HrisTokens.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(HrisSpace.s5),
            child: AppCard(
              maxWidth: 420,
              padding: const EdgeInsets.all(HrisSpace.s6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(icon, size: 56, color: scheme.error),
                  const SizedBox(height: HrisSpace.s4),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: HrisType.heading, fontWeight: HrisType.semibold, height: 1.25, color: t.text),
                  ),
                  const SizedBox(height: HrisSpace.s3),
                  Text(body, textAlign: TextAlign.center, style: TextStyle(fontSize: HrisType.sm, height: 1.5, color: t.muted)),
                  const SizedBox(height: HrisSpace.s5),
                  FilledButton(onPressed: () => primaryAction(), child: Text(primaryLabel)),
                  const SizedBox(height: HrisSpace.s3),
                  if (verdict != GateVerdict.permissionDenied)
                    OutlinedButton(onPressed: () => onRetry(), child: const Text('Check again')),
                  const SizedBox(height: HrisSpace.s4),
                  TextButton(
                    onPressed: () => context.read<SessionController>().logout(),
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
