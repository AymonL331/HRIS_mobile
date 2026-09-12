import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/session_controller.dart';
import '../../core/config/app_env.dart';
import '../../core/config/env_store.dart';
import '../../core/http/api_exception.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/brand_mark.dart';
import '../../shared/widgets/message_banner.dart';
import 'env_settings_sheet.dart';

/// Same credentials as the web app: company (or branch) code, username or
/// email, password. The environment switch picks which backend those go to.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _companyCode = TextEditingController();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};
  bool _dismissedReason = false;

  @override
  void dispose() {
    _companyCode.dispose();
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  /// The server's words, except where the app can say it better.
  static String humanize(ApiException e) {
    if (e.mobileAccessDisabled) {
      return "Your account isn't enabled for the mobile app yet. Ask HR to turn on mobile access for you.";
    }
    if (e.code == 'INVALID_ENVELOPE' || e.isNetwork) {
      return '${e.message}\nCheck the server address under Advanced.';
    }
    return e.message;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _fieldErrors = const {};
      _dismissedReason = true;
    });
    try {
      await context.read<SessionController>().login(
            companyCode: _companyCode.text.trim(),
            identifier: _identifier.text.trim(),
            password: _password.text,
          );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.isValidation && e.fieldErrors.isNotEmpty) {
          _fieldErrors = e.fieldErrors;
        } else {
          _error = humanize(e);
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final envStore = context.watch<EnvStore>();
    final selected = envStore.config.selected;
    final reason = session.state is SignedOut ? (session.state as SignedOut).reason : null;
    const envs = AppEnv.values;
    final t = HrisTokens.of(context);

    // The web login: one auth card on the page background — brand, a muted
    // line, the fields recessed into the card, a full-width primary button.
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(HrisSpace.s5),
            child: AppCard(
              maxWidth: 380,
              padding: const EdgeInsets.all(HrisSpace.s6),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const BrandMark(size: BrandMarkSize.auth),
                    const SizedBox(height: HrisSpace.s2),
                    Text(
                      'Employee time clock',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: HrisType.sm, color: t.muted, height: 1.4),
                    ),
                    const SizedBox(height: HrisSpace.s4),
                    SegmentedButton<AppEnv>(
                      segments: [for (final e in envs) ButtonSegment(value: e, label: Text(e.label))],
                      selected: {selected},
                      showSelectedIcon: false,
                      onSelectionChanged: _busy ? null : (s) => session.switchEnv(s.first),
                    ),
                    const SizedBox(height: HrisSpace.s4),
                    if (reason != null && !_dismissedReason) ...[
                      MessageBanner.info(reason, onClose: () => setState(() => _dismissedReason = true)),
                      const SizedBox(height: 12),
                    ],
                    if (_error != null) ...[
                      MessageBanner.error(_error!),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: _companyCode,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.organizationName],
                      decoration: InputDecoration(
                        labelText: 'Company or branch code',
                        errorText: _fieldErrors['company_code'],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _identifier,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.username],
                      decoration: InputDecoration(
                        labelText: 'Username or email',
                        errorText: _fieldErrors['identifier'],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _busy ? null : _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        errorText: _fieldErrors['password'],
                        suffixIcon: IconButton(
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                          : const Text('Sign in'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy ? null : () => EnvSettingsSheet.show(context),
                      child: const Text('Advanced…'),
                    ),
                    const SizedBox(height: HrisSpace.s2),
                    Text(
                      envStore.config.baseUrl,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: HrisType.xs, color: t.muted, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
