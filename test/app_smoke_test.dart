import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/app.dart';
import 'package:hris_mobile/core/auth/session_controller.dart';
import 'package:hris_mobile/core/auth/session_store.dart';
import 'package:hris_mobile/core/config/env_store.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('a cold start with no session lands on the login screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final env = EnvStore();
    await env.load();
    final session = SessionController(env: env, store: InMemorySessionStore(), appVersion: '1.0.0');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<EnvStore>.value(value: env),
          ChangeNotifierProvider<SessionController>.value(value: session),
        ],
        child: const HrisApp(),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget); // splash

    await session.bootstrap();
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Company or branch code'), findsOneWidget);
    expect(find.text('Main HRIS'), findsOneWidget);
    expect(find.text('Sandbox'), findsOneWidget);
  });
}
