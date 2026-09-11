import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/session_controller.dart';
import '../../core/config/app_env.dart';
import '../../core/config/env_store.dart';
import '../../core/location/location_fix.dart';

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
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (ok == true && context.mounted) await context.read<SessionController>().logout();
  }

  Future<void> _switchEnv(BuildContext context) async {
    final current = context.read<EnvStore>().config.selected;
    final envs = [AppEnv.main, AppEnv.sandbox, if (kDebugMode) AppEnv.emulator];
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

    return ListView(
      children: [
        const _Header('Account'),
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
        const Divider(),
        const _Header('Environment'),
        ListTile(
          leading: const Icon(Icons.cloud_outlined),
          title: Text(env.selected.label),
          subtitle: Text(env.baseUrl),
          trailing: const Icon(Icons.swap_horiz),
          onTap: () => _switchEnv(context),
        ),
        const Divider(),
        const _Header('About'),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('Version'),
          subtitle: Text(session.appVersion),
        ),
        if (kDebugMode) ...[
          const Divider(),
          const _Header('Developer'),
          const _SimulateMockedSwitch(),
        ],
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OutlinedButton.icon(
            onPressed: () => _confirmLogout(context),
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// Debug builds only: the emulator's `geo fix` never reports a mocked position,
/// so this is how the "Mock location detected" refusal is exercised.
class _SimulateMockedSwitch extends StatefulWidget {
  const _SimulateMockedSwitch();

  @override
  State<_SimulateMockedSwitch> createState() => _SimulateMockedSwitchState();
}

class _SimulateMockedSwitchState extends State<_SimulateMockedSwitch> {
  @override
  Widget build(BuildContext context) => SwitchListTile(
        secondary: const Icon(Icons.bug_report_outlined),
        title: const Text('Simulate mocked GPS'),
        subtitle: const Text('The next punch is treated as a fake-GPS reading'),
        value: GeolocatorFixService.simulateMocked,
        onChanged: (v) => setState(() => GeolocatorFixService.simulateMocked = v),
      );
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                letterSpacing: 1.1,
              ),
        ),
      );
}
