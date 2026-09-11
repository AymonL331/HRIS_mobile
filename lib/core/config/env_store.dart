import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_env.dart';

/// Loads and persists the [EnvConfig] (selected backend + the two URLs).
///
/// Only the environment choice and URL overrides live here — never a token;
/// tokens are in secure storage keyed by [EnvConfig.storageKey]. Switching the
/// environment is owned by the session (it logs out first), which then calls
/// [select].
class EnvStore extends ChangeNotifier {
  static const _kSelected = 'env.selected';
  static const _kMainUrl = 'env.mainUrl';
  static const _kSandboxUrl = 'env.sandboxUrl';

  EnvConfig _config = const EnvConfig.defaults();
  bool _loaded = false;

  EnvConfig get config => _config;
  bool get loaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    var selected = AppEnv.parse(prefs.getString(_kSelected));
    // The emulator preset is a debug convenience; a release build that somehow
    // stored it falls back to Main rather than pointing at 10.0.2.2.
    if (selected == AppEnv.emulator && kReleaseMode) selected = AppEnv.main;
    _config = EnvConfig(
      selected: selected,
      mainUrl: EnvConfig.normalizeUrl(prefs.getString(_kMainUrl) ?? '') ?? EnvConfig.defaultMainUrl,
      sandboxUrl: EnvConfig.normalizeUrl(prefs.getString(_kSandboxUrl) ?? '') ?? EnvConfig.defaultSandboxUrl,
    );
    _loaded = true;
    notifyListeners();
  }

  Future<void> select(AppEnv env) async {
    if (env == _config.selected) return;
    _config = _config.copyWith(selected: env);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSelected, env.name);
  }

  /// Save both URLs. Throws [FormatException] naming the bad field so the sheet
  /// can show it inline; nothing is stored when either is invalid.
  Future<void> setUrls({required String mainUrl, required String sandboxUrl}) async {
    final main = EnvConfig.normalizeUrl(mainUrl);
    final sandbox = EnvConfig.normalizeUrl(sandboxUrl);
    if (main == null) throw const FormatException('mainUrl');
    if (sandbox == null) throw const FormatException('sandboxUrl');
    _config = _config.copyWith(mainUrl: main, sandboxUrl: sandbox);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMainUrl, main);
    await prefs.setString(_kSandboxUrl, sandbox);
  }

  Future<void> resetUrls() async {
    _config = _config.copyWith(mainUrl: EnvConfig.defaultMainUrl, sandboxUrl: EnvConfig.defaultSandboxUrl);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kMainUrl);
    await prefs.remove(_kSandboxUrl);
  }
}
