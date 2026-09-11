import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/session_controller.dart';
import '../../core/http/api_exception.dart';
import '../../core/http/endpoints.dart';
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

/// Change the signed-in account's password.
///
/// Two modes, one screen. FORCED: the server refuses every other route until a
/// provisioned or admin-reset password is replaced (`PASSWORD_CHANGE_REQUIRED`),
/// so the root shows this instead of the shell, with sign-out as the only other
/// way off it. VOLUNTARY: pushed from Settings, pops on success.
///
/// The server re-verifies the current password and applies the 8–72 rule; the
/// same rules are checked here first so the common mistakes never cost a round
/// trip. On success the SAME token keeps working (the gate is on the user row).
class ChangePasswordScreen extends StatefulWidget {
  final bool forced;

  const ChangePasswordScreen({super.key, required this.forced});

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
      session.markPasswordChanged();
      if (!widget.forced) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password changed.')));
        Navigator.of(context).pop();
      }
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
        automaticallyImplyLeading: !widget.forced,
        actions: [
          if (widget.forced)
            TextButton(onPressed: _busy ? null : () => session.logout(), child: const Text('Sign out')),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.forced) ...[
                  const MessageBanner.info(
                    'This password was set for you. Choose your own before using the app — it is the same password as the HRIS website.',
                  ),
                  const SizedBox(height: 16),
                ],
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
    );
  }
}
