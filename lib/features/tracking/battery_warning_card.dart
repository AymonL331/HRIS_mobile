import 'package:flutter/material.dart';

import '../../shared/tokens.dart';
import '../../shared/widgets/app_card.dart';
import 'background_running.dart';

/// Warns, on the Time Clock, while the phone may stop the tracking service —
/// and offers the fix in one tap.
///
/// The setup wizard already asks for this once, but that step is skippable and
/// the setting drifts (a battery-saver prompt, a system update, an OEM cleaner).
/// A trail from 2026-09-16 showed the service killed and restarted SIX times in
/// one shift on a phone that had not been exempted, so the reminder lives where
/// the recording is and re-checks whenever the app comes back to the foreground.
///
/// Shows nothing while the phone is exempt or the state is unknown — see
/// [BackgroundRunning]. On brands that add their own background killer it also
/// names those steps, because no dialog can set them (user, 2026-09-17: four
/// test phones, four different battery menus).
class BatteryWarningCard extends StatelessWidget {
  const BatteryWarningCard({super.key});

  @override
  Widget build(BuildContext context) {
    return BackgroundRunning(
      builder: (context, state) {
        if (state.unrestricted != false) return const SizedBox.shrink();
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
                        style: TextStyle(
                          fontSize: HrisType.md,
                          fontWeight: HrisType.semibold,
                          height: 1.35,
                          color: t.warning.text,
                        ),
                      ),
                      const SizedBox(height: HrisSpace.s1),
                      Text(
                        'Your phone is allowed to stop HRIS in the background. When it does, your shift shows gaps you did not cause.',
                        style: TextStyle(fontSize: HrisType.xs, height: 1.45, color: t.muted),
                      ),
                      const SizedBox(height: HrisSpace.s2),
                      OutlinedButton.icon(
                        onPressed: state.busy ? null : state.allow,
                        icon: const Icon(Icons.battery_saver),
                        label: Text(state.busy ? 'Opening settings…' : 'Allow in the background'),
                      ),
                      if (state.hint != null) ...[
                        const SizedBox(height: HrisSpace.s2),
                        OemHintLines(hint: state.hint!, color: t.muted),
                        // Only when the steps are on the page this button opens.
                        if (state.hint!.onAppInfoPage) ...[
                          const SizedBox(height: HrisSpace.s1),
                          TextButton.icon(
                            onPressed: state.openSettings,
                            icon: const Icon(Icons.open_in_new, size: 18),
                            label: const Text('Open app settings'),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
