import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/config/env_store.dart';
import 'package:hris_mobile/features/app_update/apk_installer.dart';
import 'package:hris_mobile/features/app_update/app_update_api.dart';
import 'package:hris_mobile/features/app_update/app_update_controller.dart';
import 'package:hris_mobile/features/app_update/app_update_models.dart';
import 'package:hris_mobile/features/app_update/update_gate.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// IN-APP UPDATE (2026-09-15): the app asks its server for the newest published APK,
// downloads it, refuses it unless the SHA-256 matches, and hands it to Android's
// installer. A failed check never nags; "required" only ever means "there is
// something newer to install".

AppRelease release({int code = 12, String name = '1.7.1', String sha = '', String? notes}) => AppRelease(
      versionName: name,
      versionCode: code,
      sizeBytes: 72 * 1024 * 1024,
      sha256: sha,
      downloadPath: '/api/mobile-app/download/$code',
      notes: notes,
    );

class FakeUpdateApi implements AppUpdateApi {
  UpdateInfo info;
  Object? latestError;
  Object? downloadError;
  int downloads = 0;
  final String path;

  FakeUpdateApi(this.info, {this.path = '/tmp/hris-update.apk'});

  @override
  Future<UpdateInfo> latest() async {
    if (latestError != null) throw latestError!;
    return info;
  }

  @override
  Future<File> download(AppRelease release, {void Function(double progress)? onProgress}) async {
    downloads += 1;
    if (downloadError != null) throw downloadError!;
    onProgress?.call(0.5);
    onProgress?.call(1);
    final f = File('${Directory.systemTemp.createTempSync('hris-upd-').path}/u.apk')..writeAsBytesSync([1, 2, 3]);
    return f;
  }
}

class FakeInstaller implements ApkInstaller {
  bool allowed;
  final List<String> installed = [];
  int settingsOpened = 0;

  FakeInstaller({this.allowed = true});

  @override
  Future<bool> canInstall() async => allowed;

  @override
  Future<void> install(String path) async => installed.add(path);

  @override
  Future<void> openInstallSettings() async => settingsOpened += 1;
}

Future<EnvStore> loadedEnv() async {
  SharedPreferences.setMockInitialValues({});
  final env = EnvStore();
  await env.load();
  return env;
}

void main() {
  group('the verdict', () {
    test('nothing newer: none; newer: available; newer AND below the minimum: required', () {
      expect(UpdateInfo(latest: release(code: 11)).verdictFor(11), UpdateVerdict.none);
      expect(const UpdateInfo().verdictFor(11), UpdateVerdict.none);
      expect(UpdateInfo(latest: release(code: 12)).verdictFor(11), UpdateVerdict.available);
      expect(UpdateInfo(latest: release(code: 12), minVersionCode: 12).verdictFor(11), UpdateVerdict.required);
    });

    test('a minimum above every published build never locks anyone out', () {
      expect(UpdateInfo(latest: release(code: 11), minVersionCode: 20).verdictFor(11), UpdateVerdict.none);
    });

    test('the build number is read from the app version string', () {
      expect(versionCodeOf('1.7.0+11'), 11);
      expect(versionCodeOf('1.7.0'), 0);
      expect(versionCodeOf('garbage+x'), 0);
    });
  });

  group('the download', () {
    test('checks the SHA-256: a match returns the file, a mismatch deletes it and says so', () async {
      final bytes = List<int>.generate(50000, (i) => i % 251);
      final good = sha256.convert(bytes).toString();
      final cache = Directory.systemTemp.createTempSync('hris-cache-');
      final client = MockClient.streaming((request, _) async {
        expect(request.url.path, '/api/mobile-app/download/12');
        return http.StreamedResponse(Stream.fromIterable([bytes.sublist(0, 20000), bytes.sublist(20000)]), 200,
            contentLength: bytes.length);
      });
      final api = HttpAppUpdateApi(baseUrl: 'https://sandbox.test', appVersion: '1.7.0+11', client: client, cacheDir: () async => cache);

      final progress = <double>[];
      final file = await api.download(release(sha: good), onProgress: progress.add);
      expect(file.readAsBytesSync(), bytes);
      expect(progress.last, 1.0);

      await expectLater(api.download(release(sha: 'f' * 64)), throwsA(isA<AppUpdateException>()));
      expect(Directory('${cache.path}/updates').listSync(), isEmpty, reason: 'a damaged file is never left to install');
    });

    test('the latest check needs no token and reads the envelope', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/mobile-app/latest');
        expect(request.headers.containsKey('Authorization'), isFalse);
        return http.Response(
          jsonEncode({
            'success': true,
            'message': '',
            'data': {
              'latest': {'version_name': '1.7.1', 'version_code': 12, 'size_bytes': 10, 'sha256': 'AB', 'notes': null, 'download_path': '/api/mobile-app/download/12'},
              'min_version_code': 0,
            },
            'error': null,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final info = await HttpAppUpdateApi(baseUrl: 'https://sandbox.test', appVersion: '1.7.0+11', client: client).latest();
      expect(info.latest!.versionCode, 12);
      expect(info.latest!.sha256, 'ab');
    });
  });

  group('the controller', () {
    test('update: asks for the install permission first when Android has not allowed it', () async {
      final env = await loadedEnv();
      final api = FakeUpdateApi(UpdateInfo(latest: release()));
      final installer = FakeInstaller(allowed: false);
      final c = AppUpdateController(env: env, currentVersionCode: 11, currentVersionName: '1.7.0', apiFor: (_) => api, installer: installer);
      await c.check(force: true);
      expect(c.verdict, UpdateVerdict.available);

      await c.startUpdate();
      expect(c.phase, UpdatePhase.needsPermission);
      expect(api.downloads, 0);

      installer.allowed = true;
      await c.onResumed(); // back from Android's setting
      expect(api.downloads, 1);
      expect(installer.installed, hasLength(1));
      expect(c.phase, UpdatePhase.idle);
    });

    test('a failed download is reported in its own words; a failed CHECK is silent', () async {
      final env = await loadedEnv();
      final api = FakeUpdateApi(UpdateInfo(latest: release()))..downloadError = const AppUpdateException('The downloaded update was damaged. Try again.');
      final c = AppUpdateController(env: env, currentVersionCode: 11, currentVersionName: '1.7.0', apiFor: (_) => api, installer: FakeInstaller());
      await c.check(force: true);
      await c.startUpdate();
      expect(c.phase, UpdatePhase.failed);
      expect(c.error, contains('damaged'));

      final offline = FakeUpdateApi(const UpdateInfo())..latestError = const SocketException('offline');
      final quiet = AppUpdateController(env: env, currentVersionCode: 11, currentVersionName: '1.7.0', apiFor: (_) => offline, installer: FakeInstaller());
      await quiet.check(force: true);
      expect(quiet.verdict, UpdateVerdict.none);
      expect(quiet.error, isNull);
    });

    test('Later hides the prompt until something newer is published', () async {
      final env = await loadedEnv();
      final api = FakeUpdateApi(UpdateInfo(latest: release(code: 12)));
      final c = AppUpdateController(env: env, currentVersionCode: 11, currentVersionName: '1.7.0', apiFor: (_) => api, installer: FakeInstaller());
      await c.check(force: true);
      expect(c.showsPrompt, isTrue);
      c.dismiss();
      expect(c.showsPrompt, isFalse);
      await c.check(force: true);
      expect(c.showsPrompt, isFalse, reason: 'the same release stays dismissed');
      api.info = UpdateInfo(latest: release(code: 13, name: '1.7.2'));
      await c.check(force: true);
      expect(c.showsPrompt, isTrue);
    });
  });

  group('the gate', () {
    Future<AppUpdateController> mountGate(WidgetTester tester, UpdateInfo info, {int current = 11}) async {
      final env = await loadedEnv();
      final c = AppUpdateController(env: env, currentVersionCode: current, currentVersionName: '1.7.0', apiFor: (_) => FakeUpdateApi(info), installer: FakeInstaller());
      await tester.pumpWidget(ChangeNotifierProvider<AppUpdateController>.value(
        value: c,
        child: MaterialApp(
          builder: (context, child) => UpdateGate(child: child!),
          home: const Scaffold(body: Text('THE APP')),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      return c;
    }

    testWidgets('an available update is a card over the app: Later hides it', (tester) async {
      await mountGate(tester, UpdateInfo(latest: release(notes: 'The Reason label.')));
      expect(find.text('THE APP'), findsOneWidget);
      expect(find.text('Update available'), findsOneWidget);
      expect(find.textContaining('Version 1.7.1 is ready to install'), findsOneWidget);
      expect(find.textContaining("What's new: The Reason label."), findsOneWidget);
      await tester.tap(find.text('Later'));
      await tester.pump();
      expect(find.text('Update available'), findsNothing);
    });

    testWidgets('a required update replaces the app, with no Later', (tester) async {
      await mountGate(tester, UpdateInfo(latest: release(), minVersionCode: 12));
      expect(find.text('THE APP'), findsNothing);
      expect(find.text('Update required'), findsOneWidget);
      expect(find.text('Update now'), findsOneWidget);
      expect(find.text('Later'), findsNothing);
    });

    testWidgets('nothing newer: just the app', (tester) async {
      await mountGate(tester, UpdateInfo(latest: release(code: 11)));
      expect(find.text('THE APP'), findsOneWidget);
      expect(find.text('Update available'), findsNothing);
    });
  });
}
