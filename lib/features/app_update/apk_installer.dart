import 'package:flutter/services.dart';

/// Hands a downloaded APK to ANDROID'S OWN INSTALLER (MainActivity's `hris/app_update`
/// channel). Android always shows its install screen — the app can never install
/// silently — and asks once to allow "Install unknown apps" for HRIS.
abstract class ApkInstaller {
  /// Whether Android lets HRIS open the installer ("Install unknown apps" is allowed).
  Future<bool> canInstall();

  /// Opens Android's "Install unknown apps" setting for HRIS.
  Future<void> openInstallSettings();

  /// Opens the installer for the APK at [path].
  Future<void> install(String path);
}

class PlatformApkInstaller implements ApkInstaller {
  static const _channel = MethodChannel('hris/app_update');

  const PlatformApkInstaller();

  @override
  Future<bool> canInstall() async => (await _channel.invokeMethod<bool>('canInstall')) ?? false;

  @override
  Future<void> openInstallSettings() => _channel.invokeMethod<void>('openInstallSettings');

  @override
  Future<void> install(String path) => _channel.invokeMethod<void>('install', {'path': path});
}
