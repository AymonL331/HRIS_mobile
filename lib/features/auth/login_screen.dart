import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/auth/session_controller.dart';
import '../../core/config/app_env.dart';
import '../../core/config/env_store.dart';
import '../../core/http/api_exception.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/brand_mark.dart';
import '../../shared/widgets/message_banner.dart';
import 'env_settings_sheet.dart';

/// Same credentials as the web app: company (or branch) code, username (email
/// and ID number also work), password. Drawn as the website's ATLAS sign-in at
/// phone width (2026-10-17): a petrol header band with the logo and the serif
/// tagline, then the form over a quiet contour map. The environment switch and
/// Advanced — the app's own needs — sit under the form, out of the way.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  /// Field keys, for tests (the labels sit above the fields, as on the web).
  static const codeKey = Key('login-code');
  static const usernameKey = Key('login-username');
  static const passwordKey = Key('login-password');

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
        _password.clear(); // never keep a rejected password (as the web)
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
    final t = HrisTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Light status-bar icons over the petrol band.
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: t.bg,
        body: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _TopoPainter(t.border))),
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Band(dark: dark),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 28, 16, 28),
                        child: AutofillGroup(child: _form(context, t, session, envStore, selected, reason)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _form(
    BuildContext context,
    HrisTokens t,
    SessionController session,
    EnvStore envStore,
    AppEnv selected,
    String? reason,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Sign in to your account',
          style: TextStyle(fontSize: 24, fontWeight: HrisType.semibold, height: 1.2, letterSpacing: -0.36, color: t.text),
        ),
        const SizedBox(height: 22),
        if (reason != null && !_dismissedReason) ...[
          MessageBanner.info(reason, onClose: () => setState(() => _dismissedReason = true)),
          const SizedBox(height: 16),
        ],
        if (_error != null) ...[
          MessageBanner.error(_error!),
          const SizedBox(height: 16),
        ],
        _Field(
          label: 'Company or Branch Code',
          hint: "Assigned to a branch? Use your branch's code. Otherwise use the company code.",
          child: _input(
            t,
            key: LoginScreen.codeKey,
            controller: _companyCode,
            icon: Icons.apartment_outlined,
            hint: 'e.g. headoffice',
            error: _fieldErrors['company_code'],
            autofill: AutofillHints.organizationName,
          ),
        ),
        const SizedBox(height: 20),
        _Field(
          label: 'Username',
          child: _input(
            t,
            key: LoginScreen.usernameKey,
            controller: _identifier,
            icon: Icons.badge_outlined,
            hint: 'e.g. admin',
            error: _fieldErrors['identifier'],
            autofill: AutofillHints.username,
            keyboard: TextInputType.emailAddress,
          ),
        ),
        const SizedBox(height: 20),
        _Field(
          label: 'Password',
          child: _input(
            t,
            key: LoginScreen.passwordKey,
            controller: _password,
            icon: Icons.lock_outline,
            hint: '••••••••',
            error: _fieldErrors['password'],
            autofill: AutofillHints.password,
            obscure: _obscure,
            done: true,
            suffix: IconButton(
              tooltip: _obscure ? 'Show password' : 'Hide password',
              color: t.text2,
              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 26),
        SizedBox(
          height: 50,
          child: FilledButton(
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              backgroundColor: t.primary,
              foregroundColor: t.primaryContrast,
              disabledBackgroundColor: t.primary,
              disabledForegroundColor: t.primaryContrast,
              textStyle: const TextStyle(fontSize: 16, fontWeight: HrisType.semibold),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: _busy
                  ? [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: t.primaryContrast),
                      ),
                      const SizedBox(width: 10),
                      const Text('Signing in…'),
                    ]
                  : const [Text('Sign in'), SizedBox(width: 10), Icon(Icons.arrow_forward, size: 18)],
            ),
          ),
        ),
        const SizedBox(height: 26),
        Divider(height: 1, color: t.border),
        const SizedBox(height: 20),
        Text(
          'Accounts are issued by HR. Need help? Contact your HR administrator.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, height: 1.5, color: t.muted),
        ),
        const SizedBox(height: 24),
        // The app's own: which server, and where it is. Quiet, under the form.
        Center(
          child: SegmentedButton<AppEnv>(
            segments: [for (final e in AppEnv.values) ButtonSegment(value: e, label: Text(e.label))],
            selected: {selected},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: _busy ? null : (s) => session.switchEnv(s.first),
          ),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: _busy ? null : () => EnvSettingsSheet.show(context),
          child: const Text('Advanced…'),
        ),
        Text(
          envStore.config.baseUrl,
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: HrisFont.mono, fontSize: HrisType.xs, color: t.muted, height: 16 / 12),
        ),
      ],
    );
  }

  Widget _input(
    HrisTokens t, {
    required Key key,
    required TextEditingController controller,
    required IconData icon,
    required String hint,
    required String autofill,
    String? error,
    bool obscure = false,
    bool done = false,
    TextInputType? keyboard,
    Widget? suffix,
  }) {
    OutlineInputBorder edge(Color c, [double w = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c, width: w));
    return TextField(
      key: key,
      controller: controller,
      enabled: !_busy,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: !obscure,
      keyboardType: keyboard,
      textInputAction: done ? TextInputAction.done : TextInputAction.next,
      autofillHints: [autofill],
      onSubmitted: done ? (_) => _busy ? null : _submit() : null,
      style: TextStyle(fontSize: 16, color: t.text),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 16, color: t.muted),
        errorText: error,
        filled: true,
        fillColor: _busy ? t.surfaceSunken : t.surface,
        prefixIcon: Icon(icon, size: 19),
        prefixIconColor: WidgetStateColor.resolveWith(
          (s) => s.contains(WidgetState.focused) ? t.text : t.muted,
        ),
        suffixIcon: suffix,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: edge(t.borderStrong),
        enabledBorder: edge(t.borderStrong),
        disabledBorder: edge(t.borderStrong),
        focusedBorder: edge(t.focus, 1.5),
        errorBorder: edge(t.danger.text),
        focusedErrorBorder: edge(t.danger.text, 1.5),
      ),
    );
  }
}

/// A label above its control, and an optional hint below (web .atl-field).
class _Field extends StatelessWidget {
  final String label;
  final Widget child;
  final String? hint;
  const _Field({required this.label, required this.child, this.hint});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: TextStyle(fontSize: 14, fontWeight: HrisType.semibold, height: 1.3, color: t.text)),
        const SizedBox(height: 8),
        child,
        if (hint != null) ...[
          const SizedBox(height: 8),
          Text(hint!, style: TextStyle(fontSize: 13, height: 1.45, color: t.muted)),
        ],
      ],
    );
  }
}

/// The petrol header band (web .atl-plate at phone width): the logo, then
/// "Holding your team together." in Instrument Serif, over a faint dot map.
class _Band extends StatelessWidget {
  final bool dark;
  const _Band({required this.dark});

  // The web's --brand-panel / -deep / -deeper and --brand-accent, per theme.
  static const _light = [Color(0xFF0B5563), Color(0xFF0B5563), Color(0xFF084451)];
  static const _dark = [Color(0xFF1B3236), Color(0xFF13181A), Color(0xFF0F1416)];

  @override
  Widget build(BuildContext context) {
    final panel = dark ? _dark : _light;
    final ink = dark ? const Color(0xFFE7ECEC) : Colors.white;
    final accent = dark ? const Color(0xFF5CC4D4) : const Color(0xFFE3F0F1);
    final top = MediaQuery.paddingOf(context).top;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0.84, -1),
          radius: 1.3,
          colors: panel,
          stops: const [0, 0.48, 1],
        ),
      ),
      child: CustomPaint(
        painter: _DotMapPainter(dot: dark ? const Color(0xFF5CC4D4) : const Color(0xFFE3F0F1), alpha: dark ? 0.30 : 0.40),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, top + 16, 16, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BrandMark(size: BrandMarkSize.band),
              const SizedBox(height: 18),
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Holding your team\n'),
                    TextSpan(text: 'together.', style: TextStyle(fontStyle: FontStyle.italic, color: accent)),
                  ],
                ),
                style: TextStyle(fontFamily: HrisFont.serif, fontSize: 30, height: 1.0, letterSpacing: -0.36, color: ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A faint field of map dots that thickens toward the right, where the web
/// draws the islands — texture only, the copy stays on clear petrol.
class _DotMapPainter extends CustomPainter {
  final Color dot;
  final double alpha;
  const _DotMapPainter({required this.dot, required this.alpha});

  @override
  void paint(Canvas canvas, Size size) {
    const step = 9.0;
    final rnd = math.Random(7); // fixed seed: the same texture every frame
    final paint = Paint();
    for (double y = step / 2; y < size.height; y += step) {
      for (double x = step / 2; x < size.width; x += step) {
        final fx = x / size.width;
        // An island-ish blob on the right; nothing behind the logo and tagline.
        final nx = (fx - 0.78) / 0.24, ny = (y / size.height - 0.45) / 0.55;
        final d = nx * nx + ny * ny + (rnd.nextDouble() - 0.5) * 0.9;
        if (d > 1 || fx < 0.5) continue;
        paint.color = dot.withValues(alpha: alpha * (1 - d * 0.6));
        canvas.drawCircle(Offset(x, y), 1.1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotMapPainter old) => old.dot != dot || old.alpha != alpha;
}

/// The quiet contour lines behind the form (web .atl-topo): a few wobbly
/// rings in the border colour.
class _TopoPainter extends CustomPainter {
  final Color line;
  const _TopoPainter(this.line);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    void rings(Offset c, double r0, int n, double seed) {
      for (var i = 0; i < n; i++) {
        final r = r0 + i * 26.0;
        final path = Path();
        for (var a = 0; a <= 72; a++) {
          final th = a / 72 * 2 * math.pi;
          final wob = 1 + 0.10 * math.sin(3 * th + seed + i * 0.35) + 0.06 * math.cos(5 * th - seed);
          final p = c + Offset(math.cos(th) * r * wob * 1.25, math.sin(th) * r * wob);
          a == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
        path.close();
        canvas.drawPath(path, paint);
      }
    }

    rings(Offset(size.width * 1.02, size.height * 0.62), 30, 9, 0.8);
    rings(Offset(-size.width * 0.08, size.height * 0.98), 40, 8, 2.1);
  }

  @override
  bool shouldRepaint(_TopoPainter old) => old.line != line;
}
