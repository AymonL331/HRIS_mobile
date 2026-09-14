import 'package:flutter/material.dart';

import '../../shared/tokens.dart';
import '../../shared/widgets/app_card.dart';

/// RA 10173 (Data Privacy Act of 2012) consent for the MOBILE APP, shown in
/// place of the Time Clock until it is on record. Nothing is captured before it.
///
/// This is NOT the web field clock's consent. That one covers a geotag taken at
/// the moment of a punch; this app requires Android location "Allow all the
/// time" with precise accuracy, which is a wider permission, so it is asked for
/// and recorded separately (migration 059). The copy below therefore has to
/// describe the wider thing — an employee who agreed to "only when I clock"
/// has not agreed to an app that can read their position while it is closed.
///
/// The look is the web's consent card (MyTimeClockPage .legal box + a lg button).
class ConsentScreen extends StatelessWidget {
  final bool saving;
  final VoidCallback onAgree;

  const ConsentScreen({super.key, required this.saving, required this.onAgree});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(HrisSpace.s3),
      child: AppCard(
        maxWidth: 440,
        centered: true,
        padding: const EdgeInsets.all(HrisSpace.s5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.privacy_tip_outlined, size: 40, color: t.primary),
            const SizedBox(height: HrisSpace.s3),
            Text(
              'Location consent',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: HrisType.heading, fontWeight: HrisType.semibold, height: 1.25, color: t.text),
            ),
            const SizedBox(height: HrisSpace.s3),
            Text(
              'To use this app you must allow HRIS to access your location ALL THE TIME and with PRECISE '
              'accuracy. That means the app is able to read where you are even when it is closed.\n\n'
              'While you are clocked in — from the moment you clock in until you clock out — the app records '
              'where you are every few minutes, even with the screen off, and shows a notification while it '
              'does. Your clock-in and clock-out positions are also checked against your branch worksite. '
              'Outside your working hours nothing is recorded.\n\n'
              'HR can view the route you took during your shift. The records are kept for 90 days, stored '
              'securely and never shared beyond your employer.',
              style: TextStyle(fontSize: HrisType.sm, height: 1.5, color: t.text),
            ),
            const SizedBox(height: HrisSpace.s3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s3, vertical: HrisSpace.s2),
              decoration: BoxDecoration(
                color: Color.alphaBlend(t.hover, t.surface),
                borderRadius: BorderRadius.circular(HrisRadius.sm),
              ),
              child: Text(
                'By continuing you consent to your employer recording your geolocation during your working '
                'hours, including while this app is not open (Data Privacy Act of 2012, RA 10173). To withdraw '
                'it, ask HR — withdrawing means you can no longer clock in or out from this app.',
                style: TextStyle(fontSize: HrisType.xs, height: 1.45, color: t.muted),
              ),
            ),
            const SizedBox(height: HrisSpace.s5),
            FilledButton(
              onPressed: saving ? null : onAgree,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
              child: saving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : const Text('I agree — enable my Time Clock'),
            ),
          ],
        ),
      ),
    );
  }
}
