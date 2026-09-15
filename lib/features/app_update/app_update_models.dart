/// IN-APP UPDATE (2026-09-15) — what the server says is published.
///
/// The app is installed from an APK, not the Play Store, so Android never updates
/// it on its own. The server lists the newest signed APK (`GET /api/mobile-app/latest`)
/// and, optionally, the oldest build still allowed to run.
class AppRelease {
  final String versionName;
  final int versionCode;
  final int sizeBytes;
  final String sha256;
  final String? notes;
  final String downloadPath;

  const AppRelease({
    required this.versionName,
    required this.versionCode,
    required this.sizeBytes,
    required this.sha256,
    required this.downloadPath,
    this.notes,
  });

  factory AppRelease.fromJson(Map<String, dynamic> j) => AppRelease(
        versionName: (j['version_name'] ?? '') as String,
        versionCode: (j['version_code'] as num?)?.toInt() ?? 0,
        sizeBytes: (j['size_bytes'] as num?)?.toInt() ?? 0,
        sha256: ((j['sha256'] ?? '') as String).toLowerCase(),
        downloadPath: (j['download_path'] ?? '') as String,
        notes: j['notes'] as String?,
      );

  /// "69 MB" — whole megabytes, the way a phone's storage screen says it.
  String get sizeLabel => '${(sizeBytes / (1024 * 1024)).ceil()} MB';
}

enum UpdateVerdict {
  /// This build is the newest published one (or nothing is published).
  none,

  /// A newer build is published; the employee may update now or later.
  available,

  /// A newer build is published AND this build is older than the minimum the
  /// server still allows — the app cannot be used until it is updated.
  required,
}

class UpdateInfo {
  final AppRelease? latest;
  final int minVersionCode;

  const UpdateInfo({this.latest, this.minVersionCode = 0});

  factory UpdateInfo.fromJson(Map<String, dynamic> j) => UpdateInfo(
        latest: j['latest'] is Map<String, dynamic> ? AppRelease.fromJson(j['latest'] as Map<String, dynamic>) : null,
        minVersionCode: (j['min_version_code'] as num?)?.toInt() ?? 0,
      );

  /// Never REQUIRED without something newer to install: a minimum set above every
  /// published build would otherwise lock everyone out with nothing to fix it.
  UpdateVerdict verdictFor(int currentVersionCode) {
    final l = latest;
    if (l == null || l.versionCode <= currentVersionCode) return UpdateVerdict.none;
    return currentVersionCode < minVersionCode ? UpdateVerdict.required : UpdateVerdict.available;
  }
}

/// The build number from the app's "1.7.0+11" version string; 0 when absent.
int versionCodeOf(String appVersion) {
  final plus = appVersion.lastIndexOf('+');
  if (plus < 0) return 0;
  return int.tryParse(appVersion.substring(plus + 1)) ?? 0;
}

/// A failure the employee should read as-is (a damaged download, the installer).
class AppUpdateException implements Exception {
  final String message;
  const AppUpdateException(this.message);

  @override
  String toString() => message;
}
