import 'package:flutter/material.dart';

import '../../shared/tokens.dart';
import 'background_running.dart';

/// Settings › Phone: whether this phone will leave HRIS running in the
/// background — ALWAYS shown, allowed or not.
///
/// The Time Clock's card only appears when something is wrong, which means a
/// phone that is set up correctly gives no sign of it. With four phones on four
/// Android skins ("Optimized" exists on one of them; the others say "Allow
/// background activity" or "Force stop to save power"), whoever is handing out
/// the phones needs a single place that answers the question in two taps —
/// without hunting through a brand's menus or plugging into a computer
/// (user, 2026-09-17).
class BackgroundRunningTile extends StatelessWidget {
  const BackgroundRunningTile({super.key});

  @override
  Widget build(BuildContext context) {
    return BackgroundRunning(
      builder: (context, state) {
        if (!state.available) return const SizedBox.shrink();
        final t = HrisTokens.of(context);
        final allowed = state.unrestricted == true;
        final unknown = state.unrestricted == null;
        final Color colour = unknown ? t.muted : (allowed ? t.success.text : t.warning.text);
        final String status = unknown ? 'Checking…' : (allowed ? 'Allowed' : 'Not allowed');

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: Icon(
                unknown
                    ? Icons.battery_unknown_outlined
                    : (allowed ? Icons.battery_charging_full_outlined : Icons.battery_alert_outlined),
                color: colour,
              ),
              title: const Text('Background running'),
              subtitle: Text(
                allowed
                    ? 'Allowed — your phone lets HRIS keep recording your location during a shift.'
                    : unknown
                        ? 'Checking this phone…'
                        : 'Not allowed — your phone may stop HRIS during a shift, leaving gaps in your record.',
              ),
              trailing: Text(
                status,
                style: TextStyle(fontSize: HrisType.xs, fontWeight: HrisType.semibold, color: colour),
              ),
            ),
            if (!allowed && !unknown)
              Padding(
                padding: const EdgeInsets.fromLTRB(HrisSpace.s4, 0, HrisSpace.s4, HrisSpace.s3),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: state.busy ? null : state.allow,
                    icon: const Icon(Icons.battery_saver),
                    label: Text(state.busy ? 'Opening settings…' : 'Allow in the background'),
                  ),
                ),
              ),
            // The brand steps are shown even when Android says "Allowed": those
            // switches are invisible to every API, so a phone can read Allowed
            // here and still be killed by its manufacturer's cleaner.
            if (state.hint != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(HrisSpace.s4, 0, HrisSpace.s4, HrisSpace.s3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                ),
              ),
          ],
        );
      },
    );
  }
}
