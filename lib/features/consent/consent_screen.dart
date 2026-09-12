import 'package:flutter/material.dart';

import '../../shared/tokens.dart';
import '../../shared/widgets/app_card.dart';

/// RA 10173 (Data Privacy Act of 2012) consent, shown in place of the Time
/// Clock until it is on record. Nothing is captured before this. The wording
/// follows the web app's, minus the face check the phone does not do; the
/// look is the web's consent card (MyTimeClockPage .legal box + a lg button).
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
              'The HRIS time clock records WHERE you clock in and out, so your attendance can be verified '
              'against your branch worksite. Your location is captured only at the moment you clock, stored '
              'securely, and never shared beyond your employer.',
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
                'By continuing you consent to your employer recording your geolocation on each clock event '
                '(Data Privacy Act of 2012, RA 10173). You can withdraw this consent from the HRIS website at any time.',
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
