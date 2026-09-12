import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/session_controller.dart';
import '../../core/location/location_gate_service.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/app_card.dart';

/// Wraps everything a signed-in user can see. While the device cannot give a
/// precise location the child is NOT built — a full-screen explanation stands
/// in its place, with the buttons that fix it. Re-checks when the app returns
/// to the foreground (the user comes back from Settings), on mount, and on
/// Retry — so the block clears itself the moment the phone is set up right.
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
    if (_checking) return;
    _checking = true;
    try {
      final v = await context.read<LocationGateService>().check();
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
      return LocationBlockedScreen(verdict: v, onRetry: _check);
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
          'HRIS needs your precise location to record a punch. Allow location for this app, choosing "Precise" and "While using the app".',
          'Try again',
          onRetry,
        ),
      GateVerdict.permissionDeniedForever => (
          Icons.location_disabled_outlined,
          'Location access is blocked',
          'Location for HRIS is turned off in your phone settings. Open the app settings, tap Permissions › Location, and choose "Allow only while using the app" with "Use precise location" on.',
          'Open app settings',
          service.openAppSettings,
        ),
      GateVerdict.reducedAccuracy => (
          Icons.gps_not_fixed,
          'Precise location is required',
          'Location is set to "Approximate", which is only good to a few kilometres. In the app settings, under Permissions › Location, turn on "Use precise location".',
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
