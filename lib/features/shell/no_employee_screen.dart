import 'package:flutter/material.dart';

import '../../shared/tokens.dart';
import '../../shared/widgets/app_card.dart';

/// Shown on the Time Clock and Attendance tabs when the signed-in login has no
/// employee record — a Super Admin or a special back-office account. Those can
/// sign in (to check the app, the environment, a password) but have nothing to
/// clock and no DTR; every `/api/me/*` call would 404, so say so instead.
/// Drawn as the web EmptyState card.
class NoEmployeeScreen extends StatelessWidget {
  final String what;

  const NoEmployeeScreen({super.key, required this.what});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(HrisSpace.s4),
        child: AppCard(
          maxWidth: 440,
          centered: true,
          padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s5, vertical: HrisSpace.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The icon as the web's neutral gate mark.
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: t.neutral.bg, borderRadius: BorderRadius.circular(HrisRadius.control)),
                child: Icon(Icons.admin_panel_settings_outlined, size: 22, color: t.text2),
              ),
              const SizedBox(height: HrisSpace.s3),
              Text(
                'No employee record',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: HrisType.md, fontWeight: HrisType.semibold, height: 24 / 16, color: t.text),
              ),
              const SizedBox(height: HrisSpace.s1),
              Text(
                'This login is not linked to an employee, so there is no $what to show. '
                'The time clock is for employee accounts; this account can still use Settings.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
