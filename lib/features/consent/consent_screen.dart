import 'package:flutter/material.dart';

/// RA 10173 (Data Privacy Act of 2012) consent, shown in place of the Time
/// Clock until it is on record. Nothing is captured before this. The wording
/// follows the web app's, minus the face check the phone does not do.
class ConsentScreen extends StatelessWidget {
  final bool saving;
  final VoidCallback onAgree;

  const ConsentScreen({super.key, required this.saving, required this.onAgree});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.privacy_tip_outlined, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text('Location consent', style: text.headlineSmall),
          const SizedBox(height: 12),
          Text(
            'The HRIS time clock records WHERE you clock in and out, so your attendance can be verified '
            'against your branch worksite. Your location is captured only at the moment you clock, stored '
            'securely, and never shared beyond your employer.',
            style: text.bodyLarge?.copyWith(height: 1.45),
          ),
          const SizedBox(height: 12),
          Text(
            'By continuing you consent to your employer recording your geolocation on each clock event '
            '(Data Privacy Act of 2012, RA 10173). You can withdraw this consent from the HRIS website at any time.',
            style: text.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: saving ? null : onAgree,
            child: saving
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Text('I agree — enable my Time Clock'),
          ),
        ],
      ),
    );
  }
}
