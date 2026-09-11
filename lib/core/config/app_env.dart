/// Which HRIS backend the app talks to.
///
/// `main` and `sandbox` are the two the user picks on the login screen — the
/// same split as the web app (real HRIS vs the hris_test sandbox). There is
/// deliberately no third preset: on the Android emulator, point Sandbox at
/// `http://10.0.2.2:5001` from Login › Advanced (10.0.2.2 is the host PC).
enum AppEnv {
  main,
  sandbox;

  String get label => switch (this) {
        AppEnv.main => 'Main HRIS',
        AppEnv.sandbox => 'Sandbox',
      };

  static AppEnv parse(String? raw) => AppEnv.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => AppEnv.main,
      );
}

/// The resolved environment: the selected backend plus the two editable URLs.
///
/// Defaults are compiled in with `--dart-define` so a release build ships the
/// production host without a code change; a stored override (the "Advanced"
/// sheet on the login screen) wins over the compiled default until reset.
class EnvConfig {
  static const defaultMainUrl = String.fromEnvironment(
    'HRIS_MAIN_URL',
    defaultValue: 'http://192.168.137.1:5000',
  );
  static const defaultSandboxUrl = String.fromEnvironment(
    'HRIS_SANDBOX_URL',
    defaultValue: 'https://turbine-chamomile-financial.ngrok-free.dev',
  );
  final AppEnv selected;
  final String mainUrl;
  final String sandboxUrl;

  const EnvConfig({
    required this.selected,
    required this.mainUrl,
    required this.sandboxUrl,
  });

  const EnvConfig.defaults()
      : selected = AppEnv.main,
        mainUrl = defaultMainUrl,
        sandboxUrl = defaultSandboxUrl;

  /// The base URL every request is built on, without a trailing slash.
  String get baseUrl => switch (selected) {
        AppEnv.main => mainUrl,
        AppEnv.sandbox => sandboxUrl,
      };

  /// Suffix for anything stored per environment (the session token above all),
  /// so a Sandbox token can never be sent to Main.
  String get storageKey => selected.name;

  bool get isDefaultUrls => mainUrl == defaultMainUrl && sandboxUrl == defaultSandboxUrl;

  EnvConfig copyWith({AppEnv? selected, String? mainUrl, String? sandboxUrl}) => EnvConfig(
        selected: selected ?? this.selected,
        mainUrl: mainUrl ?? this.mainUrl,
        sandboxUrl: sandboxUrl ?? this.sandboxUrl,
      );

  /// Trim, drop a trailing slash. Returns null when the value is not a usable
  /// http(s) origin — the caller shows [validateUrl]'s message instead.
  static String? normalizeUrl(String raw) {
    var s = raw.trim();
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    final uri = Uri.tryParse(s);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
      return null;
    }
    return s;
  }

  /// Human message for a bad URL, or null when it is fine.
  static String? validateUrl(String raw) {
    if (raw.trim().isEmpty) return 'Enter the server address.';
    if (normalizeUrl(raw) == null) return 'Use a full address starting with http:// or https://.';
    return null;
  }
}
