import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/session_controller.dart';
import '../../core/config/app_env.dart';
import '../../core/config/env_store.dart';
import '../../shared/button_styles.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/page_header.dart';

/// Who is signed in, where the app is pointed, the version, and the way out.
class SettingsScreen extends StatelessWidget {
  /// Pushes the voluntary change-password screen (wired by the shell).
  final VoidCallback? onChangePassword;

  const SettingsScreen({super.key, this.onChangePassword});

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text("You'll need your company code, username and password to sign back in."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: HrisButtonStyles.danger(ctx),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) await context.read<SessionController>().logout();
  }

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
            subtitle: Text([if (tenant != null) tenant.name, if (user?.email.isNotEmpty ?? false) user!.email].join(' · ')),
          ),
          ListTile(
            leading: const Icon(Icons.password_outlined),
            title: const Text('Change password'),
            enabled: onChangePassword != null,
            subtitle: const Text('Same password as the HRIS website'),
            onTap: onChangePassword,
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
        const SizedBox(height: HrisSpace.s5),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s4),
          child: OutlinedButton.icon(
            onPressed: () => _confirmLogout(context),
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: t.danger.text,
              iconColor: t.danger.text,
              side: BorderSide(color: t.danger.border),
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ),
      ],
    );
  }
}


