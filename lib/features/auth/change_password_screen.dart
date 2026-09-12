import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/session_controller.dart';
import '../../core/http/api_exception.dart';
import '../../core/http/endpoints.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/message_banner.dart';

/// Mirrors validators/auth.validator.js#validateChangePassword, plus the
/// confirm field that only exists on the phone. Empty map = nothing wrong.
Map<String, String> validateChangePassword({required String current, required String next, required String confirm}) {
  final errors = <String, String>{};
  if (current.isEmpty) errors['current_password'] = 'Your current password is required.';
  if (next.isEmpty) {
    errors['new_password'] = 'A new password is required.';
  } else if (next.length < 8 || next.length > 72) {
    errors['new_password'] = 'Password must be 8–72 characters.';
  } else if (next == current) {
    errors['new_password'] = 'Choose a password different from your current one.';
  }
  if (confirm != next) errors['confirm_password'] = 'The two passwords do not match.';
  return errors;
}

/// The FORCED password change — the only way a password is set on the phone.
///
/// There is deliberately no voluntary "change password" anywhere in the app.
/// A reset starts with HR: they reset the login on the website, the server
/// issues a temporary password (`must_change_password = 1`), and it is handed
/// to the employee. The server then refuses every other route with
/// `PASSWORD_CHANGE_REQUIRED` until it is replaced, so the app's root shows
/// this screen instead of the shell, with sign-out as the only other way off
/// it. The employee types the temporary password as "current", chooses their
/// own, and confirms it.
///
/// This is the SAME `users.password_hash` the website authenticates against —
/// one credential, two surfaces. A password chosen here works on the website
/// immediately, and one chosen on the website works here, with nothing to sync.
///
/// The server re-verifies the current password and applies the 8–72 rule; the
/// same rules are checked here first so the common mistakes never cost a round
/// trip. On success the SAME token keeps working (the gate is on the user row).
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final local = validateChangePassword(current: _current.text, next: _next.text, confirm: _confirm.text);
    setState(() {
      _error = null;
      _fieldErrors = local;
    });
    if (local.isNotEmpty) return;

    setState(() => _busy = true);
    final session = context.read<SessionController>();
    try {
      await session.guard(() => session.client.post(
            Endpoints.changePassword,
            body: {'current_password': _current.text, 'new_password': _next.text},
          ));
      if (!mounted) return;
      // No pop and no snackbar: clearing the flag flips the app root from this
      // screen to the shell, which is the confirmation.
      session.markPasswordChanged();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.isValidation && e.fieldErrors.isNotEmpty) {
          _fieldErrors = e.fieldErrors;
        } else {
          _error = e.message;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Change password'),
        // No back arrow: there is nowhere to go back TO until the password is
        // replaced. Signing out is the only other way off this screen.
        automaticallyImplyLeading: false,
        actions: [
          TextButton(onPressed: _busy ? null : () => session.logout(), child: const Text('Sign out')),
        ],
      ),
      // The web ChangePasswordPage: the same auth card as the login.
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: AppCard(
            maxWidth: 420,
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const MessageBanner.info(
                  'This password was set for you by HR. Choose your own before using the app — it is the '
                  'same password as the HRIS website, so it changes there too.',
                ),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  MessageBanner.error(_error!),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _current,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: 'Current password', errorText: _fieldErrors['current_password']),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _next,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'New password',
                    helperText: '8 to 72 characters.',
                    errorText: _fieldErrors['new_password'],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirm,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _busy ? null : _submit(),
                  decoration: InputDecoration(
                    labelText: 'Confirm new password',
                    errorText: _fieldErrors['confirm_password'],
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Show passwords' : 'Hide passwords',
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
                      : const Text('Save new password'),
                ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }
}
