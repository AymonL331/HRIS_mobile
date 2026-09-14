import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/session_controller.dart';
import '../../core/config/app_env.dart';
import '../../core/config/env_store.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/page_header.dart';

/// Who is signed in, where the app is pointed, and the version.
///
/// Sign out is NOT here any more: it lives in the sidebar's footer, one tap from
/// anywhere (user, 2026-09-14 — see AppDrawer).
///
/// Deliberately carries NO change-password action: a password reset starts with
/// HR issuing a temporary credential, and the holder replaces it through the
/// forced screen on their next sign-in. See the Password tile below.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _switchEnv(BuildContext context) async {
    final current = context.read<EnvStore>().config.selected;
    const envs = AppEnv.values;
    final target = await showDialog<AppEnv>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Switch environment'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('Switching signs you out of the current one.'),
          ),
          for (final e in envs)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, e),
              child: Row(
                children: [
                  Icon(e == current ? Icons.radio_button_checked : Icons.radio_button_off, size: 20),
                  const SizedBox(width: 12),
                  Text(e.label),
                ],
              ),
            ),
        ],
      ),
    );
    if (target != null && target != current && context.mounted) {
      await context.read<SessionController>().switchEnv(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final env = context.watch<EnvStore>().config;
    final user = session.user;
    final tenant = session.tenant;

    final t = HrisTokens.of(context);
    // Each group is a web card of rows under an uppercase section label; the
    // rows are the same tiles as before.
    Widget group(List<Widget> tiles) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s4),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (var i = 0; i < tiles.length; i += 1) ...[
              if (i > 0) Divider(height: 1, indent: HrisSpace.s4, color: t.border),
              tiles[i],
            ],
          ],
        ),
      ),
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: HrisSpace.s5),
      children: [
        const SectionLabel('Account'),
        group([
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(user?.username ?? '—'),
            subtitle: Text(
              [if (tenant != null) tenant.name, if (user?.email.isNotEmpty ?? false) user!.email].join(' · '),
            ),
          ),
          // NOT a button. Changing a password starts with HR, not with the
          // holder: they reset the login, the server issues a temporary
          // password, and the employee replaces it on their next sign-in
          // (`must_change_password`). Offering a self-service "change" here
          // would be a second, weaker door to the same credential — one that
          // skips the handover the whole flow is built around. So this tile
          // only says where the real route is.
          const ListTile(
            leading: Icon(Icons.password_outlined),
            title: Text('Password'),
            subtitle: Text(
              'The same password as the HRIS website. To reset it, ask HR — they issue a temporary '
              'password, and you choose your own the next time you sign in here or on the website.',
            ),
            isThreeLine: true,
          ),
        ]),
        const SectionLabel('Environment'),
        group([
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: Text(env.selected.label),
            subtitle: Text(env.baseUrl),
            trailing: const Icon(Icons.swap_horiz),
            onTap: () => _switchEnv(context),
          ),
        ]),
        const SectionLabel('About'),
        group([
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Version'),
            subtitle: Text(session.appVersion),
          ),
        ]),
      ],
    );
  }
}
