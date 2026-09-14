import 'package:flutter/material.dart';

import '../../core/device/device_readiness_service.dart';
import '../../core/location/location_gate_service.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/message_banner.dart';
import 'setup_illustrations.dart';
import 'setup_step.dart';

/// One step of the phone setup, explained BEFORE Android shows anything.
///
/// Why this screen exists (user, 2026-09-14): Android's location dialog offers
/// "While using the app", "Only this time" and "Don't allow" with no guidance,
/// and asking for "all the time" then throws the employee into Settings with no
/// instruction — the explanation only appeared after they pressed Back. So each
/// step here says what is about to appear, shows a drawing of it with the right
/// choice marked, and only the button under that explanation raises the dialog
/// or opens Settings.
///
/// Stateless: [LocationGate] owns the checks and passes the callbacks in.
class SetupWizardScreen extends StatelessWidget {
  final SetupStep step;
  final GateVerdict verdict;
  final DeviceReadiness device;

  /// The employee has already answered the location dialog with "Don't allow".
  final bool refusedOnce;

  final VoidCallback onOpenLocationSettings;
  final VoidCallback onRequestForeground;
  final VoidCallback onRequestBackground;
  final VoidCallback onRequestNotifications;
  final VoidCallback onRequestBattery;
  final VoidCallback onOpenAppSettings;
  final VoidCallback onCheckAgain;
  final VoidCallback onSkip;
  final VoidCallback onSignOut;

  /// Show the previous step again. Null on the first step (no back arrow, and
  /// the system back gesture leaves the app as before).
  final VoidCallback? onBack;

  /// This step is being RE-READ, not done: the phone is already past it. Its
  /// explanation is shown, but the button only moves forward — nothing raises a
  /// dialog or opens Settings for a step that is complete.
  final bool reviewing;

  /// Leave review mode, one step forward. Only used while [reviewing].
  final VoidCallback? onForward;

  const SetupWizardScreen({
    super.key,
    required this.step,
    required this.verdict,
    required this.device,
    required this.refusedOnce,
    required this.onOpenLocationSettings,
    required this.onRequestForeground,
    required this.onRequestBackground,
    required this.onRequestNotifications,
    required this.onRequestBattery,
    required this.onOpenAppSettings,
    required this.onCheckAgain,
    required this.onSkip,
    required this.onSignOut,
    this.onBack,
    this.reviewing = false,
    this.onForward,
  });

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final c = _content();
    final primaryLabel = reviewing ? 'Next' : c.primaryLabel;
    final VoidCallback primaryAction = reviewing ? (onForward ?? () {}) : c.primaryAction;
    final banner = reviewing
        ? const MessageBanner.info('You have already done this step. Tap Next to continue where you left off.')
        : c.banner;

    // The system back gesture follows the back arrow while there is a step to go
    // back to; on the first step it behaves as it always did.
    return PopScope(
      canPop: onBack == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onBack?.call();
      },
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(HrisSpace.s4),
              child: AppCard(
                maxWidth: 440,
                padding: const EdgeInsets.all(HrisSpace.s5),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        if (onBack != null) ...[
                          IconButton(
                            tooltip: 'Back',
                            onPressed: onBack,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            icon: Icon(Icons.arrow_back, color: t.text),
                          ),
                          const SizedBox(width: HrisSpace.s1),
                        ],
                        Expanded(
                          child: Text(
                            'PHONE SETUP · STEP ${step.number} OF ${SetupStep.total}',
                            style: TextStyle(
                              fontSize: HrisType.xxs,
                              letterSpacing: 0.6,
                              fontWeight: HrisType.semibold,
                              color: t.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: HrisSpace.s2),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(HrisRadius.pill),
                      child: LinearProgressIndicator(
                        value: step.number / SetupStep.total,
                        minHeight: 6,
                        backgroundColor: t.border,
                        color: t.primary,
                      ),
                    ),
                    const SizedBox(height: HrisSpace.s5),
                    Icon(c.icon, size: 44, color: t.primary),
                    const SizedBox(height: HrisSpace.s3),
                    Text(
                      c.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: HrisType.heading,
                        fontWeight: HrisType.semibold,
                        height: 1.25,
                        color: t.text,
                      ),
                    ),
                    const SizedBox(height: HrisSpace.s3),
                    Text(
                      c.intro,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: HrisType.sm, height: 1.5, color: t.muted),
                    ),
                    if (banner != null) ...[const SizedBox(height: HrisSpace.s4), banner],
                    if (c.illustration != null) ...[
                      const SizedBox(height: HrisSpace.s4),
                      Center(child: c.illustration!),
                    ],
                    if (c.steps.isNotEmpty) ...[const SizedBox(height: HrisSpace.s4), _NumberedSteps(c.steps)],
                    if (c.note != null) ...[
                      const SizedBox(height: HrisSpace.s2),
                      Text(
                        c.note!,
                        style: TextStyle(fontSize: HrisType.xs, height: 1.45, color: t.muted),
                      ),
                    ],
                    const SizedBox(height: HrisSpace.s5),
                    FilledButton(onPressed: primaryAction, child: Text(primaryLabel)),
                    if (!reviewing && c.secondaryLabel != null) ...[
                      const SizedBox(height: HrisSpace.s2),
                      OutlinedButton(onPressed: c.secondaryAction, child: Text(c.secondaryLabel!)),
                    ],
                    const SizedBox(height: HrisSpace.s3),
                    // Wrap, not Row: at a large system font size the two buttons
                    // stack instead of overflowing.
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        TextButton(onPressed: onSignOut, child: const Text('Sign out')),
                        if (reviewing)
                          const SizedBox.shrink()
                        else if (step.skippable)
                          TextButton(onPressed: onSkip, child: const Text('Skip for now'))
                        else
                          TextButton(onPressed: onCheckAgain, child: const Text('Check again')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  _StepContent _content() {
    switch (step) {
      case SetupStep.locationService:
        return _StepContent(
          icon: Icons.location_off_outlined,
          title: 'Turn on location',
          intro: "Your phone's location is switched off. HRIS records where you are while you are on duty, so it cannot run without it.",
          steps: const [
            'Tap **Open location settings**.',
            'Turn **Use location** ON.',
            'Press **Back** to return here.',
          ],
          primaryLabel: 'Open location settings',
          primaryAction: onOpenLocationSettings,
        );

      case SetupStep.locationPermission:
        return _StepContent(
          icon: Icons.location_on_outlined,
          title: 'Allow location access',
          intro: 'When you tap Continue, Android asks for your location. Read this first — it looks like the picture below.',
          banner: refusedOnce
              ? const MessageBanner.error(
                  'You tapped “Don’t allow”. HRIS cannot work without your location. Tap Continue again and choose “While using the app” or “Only this time”.',
                )
              : null,
          illustration: const PermissionDialogMock(),
          steps: const [
            'Keep **Precise** selected (the map on the left).',
            'Tap **While using the app** or **Only this time** — either one works.',
            'Do **not** tap “Don’t allow”.',
          ],
          note: 'Android does not offer “Allow all the time” here. The next step sets it in Settings, whichever of the two you picked.',
          primaryLabel: 'Continue',
          primaryAction: onRequestForeground,
        );

      case SetupStep.allowAllTheTime:
        switch (verdict) {
          case GateVerdict.permissionDeniedForever:
            return _StepContent(
              icon: Icons.location_disabled_outlined,
              title: 'Location access is blocked',
              intro:
                  'Location was refused, so Android will not ask again. You can still turn it on yourself in Settings.',
              illustration: const LocationPermissionPageMock(),
              steps: const [
                'Tap **Open app settings**.',
                'Tap **Permissions**, then **Location**.',
                'Choose **Allow all the time**.',
                'Turn **Use precise location** ON.',
                'Press **Back** until you are here again.',
              ],
              primaryLabel: 'Open app settings',
              primaryAction: onRequestBackground,
            );
          case GateVerdict.reducedAccuracy:
            return _StepContent(
              icon: Icons.gps_not_fixed,
              title: 'Precise location is required',
              intro: 'Location is set to “Approximate”, which is only good to a few kilometres. HRIS needs your exact position.',
              illustration: const LocationPermissionPageMock(highlightAlways: false),
              steps: const [
                'Tap **Open settings**.',
                'Turn **Use precise location** ON.',
                'Press **Back** to return here.',
              ],
              note: 'If the App info page opens instead, tap Permissions › Location first.',
              primaryLabel: 'Open settings',
              primaryAction: onRequestBackground,
            );
          default:
            return _StepContent(
              icon: Icons.my_location,
              title: 'Set location to "Allow all the time"',
              intro: 'Almost done. Android only offers “Allow all the time” in Settings, so HRIS opens that page for you. It looks like this:',
              illustration: const LocationPermissionPageMock(),
              steps: const [
                'Tap **Open settings**.',
                'Choose **Allow all the time**.',
                'Make sure **Use precise location** is ON.',
                'Press **Back** to return here.',
              ],
              note: 'Picked “Only this time” earlier? That is fine — this replaces it. If the App info page opens instead, tap Permissions › Location first.',
              primaryLabel: 'Open settings',
              primaryAction: onRequestBackground,
            );
        }

      case SetupStep.notifications:
        return _StepContent(
          icon: Icons.notifications_active_outlined,
          title: 'Allow notifications',
          intro: 'While you are clocked in, HRIS shows a notification that your work location is being recorded — so you always know when it is on, and when it stops.',
          illustration: const SimpleDialogMock(
            icon: Icons.notifications_outlined,
            title: 'Allow HRIS to send you notifications?',
            allow: 'Allow',
            deny: 'Don’t allow',
          ),
          steps: const ['Tap **Continue**.', 'Tap **Allow**.'],
          primaryLabel: 'Continue',
          primaryAction: onRequestNotifications,
        );

      case SetupStep.battery:
        final hint = oemBatteryHint(device.manufacturer);
        return _StepContent(
          icon: Icons.battery_charging_full_outlined,
          title: 'Let HRIS run in the background',
          intro: 'To save battery, your phone may stop apps you are not looking at. That would stop your location being recorded during your shift.',
          illustration: const SimpleDialogMock(
            icon: Icons.battery_alert_outlined,
            title: 'Let app always run in background?',
            allow: 'Allow',
            deny: 'Deny',
          ),
          steps: const ['Tap **Continue**.', 'Tap **Allow**.'],
          banner: hint == null
              ? null
              : MessageBanner.warning(
                  'On ${hint.brand} phones, also do this (names vary by model):\n• ${hint.steps.join('\n• ')}',
                ),
          primaryLabel: 'Continue',
          primaryAction: onRequestBattery,
          secondaryLabel: hint == null ? null : 'Open app settings',
          secondaryAction: hint == null ? null : onOpenAppSettings,
        );
    }
  }
}

class _StepContent {
  final IconData icon;
  final String title;
  final String intro;
  final Widget? banner;
  final Widget? illustration;
  final List<String> steps;
  final String? note;
  final String primaryLabel;
  final VoidCallback primaryAction;
  final String? secondaryLabel;
  final VoidCallback? secondaryAction;

  const _StepContent({
    required this.icon,
    required this.title,
    required this.intro,
    this.banner,
    this.illustration,
    this.steps = const [],
    this.note,
    required this.primaryLabel,
    required this.primaryAction,
    this.secondaryLabel,
    this.secondaryAction,
  });
}

/// Numbered instructions; `**text**` renders bold (the words on the button or
/// option the employee is looking for).
class _NumberedSteps extends StatelessWidget {
  final List<String> steps;

  const _NumberedSteps(this.steps);

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final base = TextStyle(fontSize: HrisType.sm, height: 1.4, color: t.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, s) in steps.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: HrisSpace.s2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: t.primarySoft),
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(fontSize: HrisType.xs, fontWeight: HrisType.semibold, color: t.primary),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(padding: const EdgeInsets.only(top: 1), child: Text.rich(_bolded(s, base))),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static TextSpan _bolded(String s, TextStyle base) {
    final parts = s.split('**');
    return TextSpan(
      style: base,
      children: [
        for (final (i, p) in parts.indexed)
          TextSpan(
            text: p,
            style: i.isOdd ? const TextStyle(fontWeight: HrisType.semibold) : null,
          ),
      ],
    );
  }
}
