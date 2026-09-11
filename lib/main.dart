import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/auth/session_controller.dart';
import 'core/auth/session_store.dart';
import 'core/config/env_store.dart';
import 'core/location/location_fix.dart';
import 'core/location/location_gate_service.dart';
import 'features/attendance/attendance_api.dart';
import 'features/time_clock/clock_api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final envStore = EnvStore();
  await envStore.load();

  String version = '0.0.0';
  try {
    final info = await PackageInfo.fromPlatform();
    version = '${info.version}+${info.buildNumber}';
  } catch (_) {
    // A missing platform channel (tests, odd hosts) must not stop the app.
  }

  final session = SessionController(env: envStore, store: SecureSessionStore(), appVersion: version);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<EnvStore>.value(value: envStore),
        ChangeNotifierProvider<SessionController>.value(value: session),
        Provider<LocationGateService>.value(value: const GeolocatorGateService()),
        Provider<LocationFixService>.value(value: const GeolocatorFixService()),
        // The Time Clock's API is built from the session by the shell; tests
        // inject a fake here instead.
        Provider<ClockApi?>.value(value: null),
        Provider<AttendanceApi?>.value(value: null),
      ],
      child: const HrisApp(),
    ),
  );

  // After the first frame so the splash is what the user sees while the stored
  // token is validated.
  session.bootstrap();
}
