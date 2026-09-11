import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_env.dart';
import '../../core/config/env_store.dart';

/// The "Advanced" sheet on the login screen: edit the Main and Sandbox server
/// addresses, or reset them to the compiled defaults. Nothing here touches a
/// session; the caller (the login screen) is signed out by definition.
class EnvSettingsSheet extends StatefulWidget {
  const EnvSettingsSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const EnvSettingsSheet(),
      );

  @override
  State<EnvSettingsSheet> createState() => _EnvSettingsSheetState();
}

class _EnvSettingsSheetState extends State<EnvSettingsSheet> {
  late final TextEditingController _main;
  late final TextEditingController _sandbox;
  String? _mainError;
  String? _sandboxError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = context.read<EnvStore>().config;
    _main = TextEditingController(text: c.mainUrl);
    _sandbox = TextEditingController(text: c.sandboxUrl);
  }

  @override
  void dispose() {
    _main.dispose();
    _sandbox.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _mainError = EnvConfig.validateUrl(_main.text);
      _sandboxError = EnvConfig.validateUrl(_sandbox.text);
    });
    if (_mainError != null || _sandboxError != null) return;
    setState(() => _saving = true);
    try {
      await context.read<EnvStore>().setUrls(mainUrl: _main.text, sandboxUrl: _sandbox.text);
      if (mounted) Navigator.of(context).pop();
    } on FormatException catch (e) {
      setState(() {
        if (e.message == 'mainUrl') _mainError = 'Use a full address starting with http:// or https://.';
        if (e.message == 'sandboxUrl') _sandboxError = 'Use a full address starting with http:// or https://.';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset() async {
    await context.read<EnvStore>().resetUrls();
    if (!mounted) return;
    final c = context.read<EnvStore>().config;
    setState(() {
      _main.text = c.mainUrl;
      _sandbox.text = c.sandboxUrl;
      _mainError = null;
      _sandboxError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Server addresses', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Where the app finds the HRIS API. Only change these if IT gave you a new address.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _main,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(labelText: 'Main HRIS', errorText: _mainError, hintText: 'https://…'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _sandbox,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(labelText: 'Sandbox', errorText: _sandboxError, hintText: 'https://…'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton(onPressed: _saving ? null : _reset, child: const Text('Reset to defaults')),
              const Spacer(),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
