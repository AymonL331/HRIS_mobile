import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/config/app_env.dart';
import 'package:hris_mobile/core/config/env_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('EnvConfig', () {
    test('defaults point Main at the hotspot and Sandbox at the Tailscale Funnel', () {
      const c = EnvConfig.defaults();
      expect(c.selected, AppEnv.main);
      expect(c.baseUrl, 'http://192.168.137.1:5000');
      // Permanent (this PC's name in the tailnet) — the reason it may be baked in.
      expect(c.copyWith(selected: AppEnv.sandbox).baseUrl, 'https://desktop-eg1b53e.tail797ea0.ts.net');
      expect(AppEnv.values, [AppEnv.main, AppEnv.sandbox]);
    });

    test('the dead ngrok host is a RETIRED default, and the current default never is', () {
      expect(EnvConfig.retiredSandboxUrls, contains('https://turbine-chamomile-financial.ngrok-free.dev'));
      expect(EnvConfig.retiredSandboxUrls, isNot(contains(EnvConfig.defaultSandboxUrl)));
    });

    test('storageKey is per environment', () {
      const c = EnvConfig.defaults();
      expect(c.storageKey, 'main');
      expect(c.copyWith(selected: AppEnv.sandbox).storageKey, 'sandbox');
    });

    test('normalizeUrl trims and strips trailing slashes; rejects non-http', () {
      expect(EnvConfig.normalizeUrl('  https://hris.example.com/  '), 'https://hris.example.com');
      expect(EnvConfig.normalizeUrl('http://10.0.0.5:5000//'), 'http://10.0.0.5:5000');
      expect(EnvConfig.normalizeUrl('hris.example.com'), isNull);
      expect(EnvConfig.normalizeUrl('ftp://x'), isNull);
      expect(EnvConfig.normalizeUrl(''), isNull);
    });

    test('validateUrl messages', () {
      expect(EnvConfig.validateUrl(''), 'Enter the server address.');
      expect(EnvConfig.validateUrl('nope'), contains('http://'));
      expect(EnvConfig.validateUrl('https://ok.test'), isNull);
    });

    test('AppEnv.parse falls back to main', () {
      expect(AppEnv.parse('sandbox'), AppEnv.sandbox);
      expect(AppEnv.parse('garbage'), AppEnv.main);
      expect(AppEnv.parse('emulator'), AppEnv.main, reason: 'retired preset');
      expect(AppEnv.parse(null), AppEnv.main);
    });
  });

  group('EnvStore', () {
    test('loads stored overrides and the selection', () async {
      SharedPreferences.setMockInitialValues({
        'env.selected': 'sandbox',
        'env.mainUrl': 'https://hris.example.com/',
      });
      final store = EnvStore();
      await store.load();
      expect(store.loaded, isTrue);
      expect(store.config.selected, AppEnv.sandbox);
      expect(store.config.mainUrl, 'https://hris.example.com');
      expect(store.config.sandboxUrl, EnvConfig.defaultSandboxUrl);
    });

    test('a stored sandbox override that is a RETIRED default is ignored and cleared', () async {
      // The trap this closes (2026-09-22): a phone that once pressed Save in
      // Advanced had the then-default ngrok host pinned in storage, and it
      // outlived the upgrade to a build whose default had moved on.
      SharedPreferences.setMockInitialValues({
        'env.sandboxUrl': 'https://turbine-chamomile-financial.ngrok-free.dev',
        'env.mainUrl': 'https://kept.example.com',
      });
      final store = EnvStore();
      await store.load();
      expect(store.config.sandboxUrl, EnvConfig.defaultSandboxUrl, reason: 'the dead host must not win');
      expect(store.config.mainUrl, 'https://kept.example.com', reason: 'an unrelated override is untouched');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('env.sandboxUrl'), isNull, reason: 'cleared, so this never has to run again');
    });

    test('a stored sandbox override that is NOT retired still wins over the default', () async {
      SharedPreferences.setMockInitialValues({'env.sandboxUrl': 'http://10.0.2.2:5001'});
      final store = EnvStore();
      await store.load();
      expect(store.config.sandboxUrl, 'http://10.0.2.2:5001');
    });

    test('a corrupt stored URL falls back to the default', () async {
      SharedPreferences.setMockInitialValues({'env.mainUrl': 'not a url'});
      final store = EnvStore();
      await store.load();
      expect(store.config.mainUrl, EnvConfig.defaultMainUrl);
    });

    test('select persists and notifies', () async {
      SharedPreferences.setMockInitialValues({});
      final store = EnvStore();
      await store.load();
      var notified = 0;
      store.addListener(() => notified++);
      await store.select(AppEnv.sandbox);
      expect(store.config.selected, AppEnv.sandbox);
      expect(notified, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('env.selected'), 'sandbox');
    });

    test('setUrls validates both, stores normalized values; resetUrls clears them', () async {
      SharedPreferences.setMockInitialValues({});
      final store = EnvStore();
      await store.load();
      await expectLater(
        store.setUrls(mainUrl: 'bad', sandboxUrl: 'https://s.test'),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', 'mainUrl')),
      );
      await store.setUrls(mainUrl: 'https://m.test/', sandboxUrl: 'https://s.test');
      expect(store.config.mainUrl, 'https://m.test');
      expect(store.config.isDefaultUrls, isFalse);
      await store.resetUrls();
      expect(store.config.isDefaultUrls, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('env.mainUrl'), isNull);
    });

    test('Save with a field left at the compiled default does NOT pin it', () async {
      // Otherwise pressing Save without changes froze THIS build's default into
      // storage, where it outlived every later build.
      SharedPreferences.setMockInitialValues({});
      final store = EnvStore();
      await store.load();
      await store.setUrls(mainUrl: EnvConfig.defaultMainUrl, sandboxUrl: 'https://custom.test');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('env.mainUrl'), isNull, reason: 'unchanged field keeps tracking the shipped default');
      expect(prefs.getString('env.sandboxUrl'), 'https://custom.test');
      // Saving the changed field back to the default un-pins it too.
      await store.setUrls(mainUrl: EnvConfig.defaultMainUrl, sandboxUrl: EnvConfig.defaultSandboxUrl);
      expect(prefs.getString('env.sandboxUrl'), isNull);
      expect(store.config.isDefaultUrls, isTrue);
    });
  });
}
