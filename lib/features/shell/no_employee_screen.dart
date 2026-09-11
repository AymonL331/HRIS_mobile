import 'package:flutter/material.dart';

/// Shown on the Time Clock and Attendance tabs when the signed-in login has no
/// employee record — a Super Admin or a special back-office account. Those can
/// sign in (to check the app, the environment, a password) but have nothing to
/// clock and no DTR; every `/api/me/*` call would 404, so say so instead.
class NoEmployeeScreen extends StatelessWidget {
  final String what;

  const NoEmployeeScreen({super.key, required this.what});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.admin_panel_settings_outlined, size: 56, color: scheme.primary),
            const SizedBox(height: 16),
            Text('No employee record', style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'This login is not linked to an employee, so there is no $what to show. '
              'The time clock is for employee accounts; this account can still use Settings.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
