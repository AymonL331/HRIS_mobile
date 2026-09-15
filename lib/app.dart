import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/auth/session_controller.dart';
import 'features/app_update/update_gate.dart';
import 'features/auth/change_password_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/splash_screen.dart';
import 'features/shell/home_shell.dart';
import 'features/shell/location_gate.dart';
import 'shared/theme.dart';

/// The HRIS mobile app. [AppRoot] switches on the session state; there is no
/// router — every screen the app has is reachable from that switch or a push
/// inside the signed-in shell.
class HrisApp extends StatelessWidget {
  const HrisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HRIS',
      // Light and dark from the web tokens; the phone's setting decides, like
      // the website's prefers-color-scheme.
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      // In-app update (2026-09-15): above every route, so a newer version is offered
      // — or a required one enforced — wherever the employee is, login included.
      builder: (context, child) => UpdateGate(child: child ?? const SizedBox.shrink()),
      home: const AppRoot(),
    );
  }
}

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SessionController>().state;
    return switch (state) {
      Bootstrapping() => const SplashScreen(),
      SignedOut() => const LoginScreen(),
      // The server refuses every other route until this password is replaced,
      // so the screen stands in for the shell (outside the location gate — a
      // password needs no GPS).
      MustChangePassword() => const ChangePasswordScreen(),
      // Everything a signed-in user can see sits behind the location gate.
      SignedIn() => const LocationGate(child: HomeShell()),
    };
  }
}
