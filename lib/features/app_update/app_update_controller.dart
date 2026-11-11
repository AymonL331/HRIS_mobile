import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/config/env_store.dart';
import '../../core/http/api_exception.dart';
import 'apk_installer.dart';
import 'app_update_api.dart';
import 'app_update_models.dart';

/// Where an update the employee started stands.
enum UpdatePhase {
  idle,

  /// Android does not yet allow HRIS to open the installer — the employee is sent
  /// to "Install unknown apps" once; coming back resumes the update.
  needsPermission,
  downloading,

  /// Android's installer has been asked to open.
  installing,
  failed,
}

/// IN-APP UPDATE (2026-09-15): checks the SELECTED server for a newer build (on
/// start, on return to the app at most every [recheckAfter], and whenever the
/// server is switched), and runs download -> verify -> Android installer.
///
/// A failed CHECK is silent — no network must never nag or block anyone. Only an
/// update the employee started reports errors.
///
/// SIGNED OUT (2026-11-07): the app is only for people given access, so the file
/// needs a sign-in. The login screen still says an update exists, but offers no
/// download: an available update is a card with OK, and a required one a screen
/// that leads to sign-in (it must not block the only way to update).
class AppUpdateController extends ChangeNotifier {
  final EnvStore env;
  final int currentVersionCode;
  final String currentVersionName;
  final AppUpdateApi Function(String baseUrl) apiFor;
  final ApkInstaller installer;
  final Duration recheckAfter;
  final DateTime Function() _now;

  AppUpdateController({
    required this.env,
    required this.currentVersionCode,
    required this.currentVersionName,
    required this.apiFor,
    this.installer = const PlatformApkInstaller(),
    this.recheckAfter = const Duration(minutes: 30),
    this._signedIn = false,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _baseUrl = env.config.baseUrl;
    env.addListener(_onEnvChanged);
  }

  UpdateInfo? _info;
  UpdateVerdict _verdict = UpdateVerdict.none;
  DateTime? _lastCheck;
  bool _checking = false;
  String _baseUrl = '';
  bool _dismissed = false;

  UpdatePhase _phase = UpdatePhase.idle;
  double _progress = 0;
  String? _error;
  File? _downloaded;
  int? _downloadedCode;
  bool _signedIn;

  /// False while the stored session is still being checked: no prompt yet, or a
  /// signed-in employee would see the login wording flash by.
  bool _sessionSettled = true;

  /// OK on the login card: gone until sign-in, where the card with Update shows.
  bool _okAtLogin = false;

  /// Sign in on the required screen: the login screen is let through.
  bool _sentToSignIn = false;

  bool get signedIn => _signedIn;
  UpdateVerdict get verdict => _verdict;
  AppRelease? get release => _info?.latest;
  UpdatePhase get phase => _phase;
  double get progress => _progress;
  String? get error => _error;

  /// The optional prompt: shown while an update is available, not dismissed, or in
  /// progress. A REQUIRED update is a full screen instead (see UpdateGate).
  bool get showsPrompt {
    if (_verdict != UpdateVerdict.available || !_sessionSettled) return false;
    if (_phase != UpdatePhase.idle) return true;
    return _signedIn ? !_dismissed : !_okAtLogin;
  }

  /// The full screen a required update takes over the app with.
  bool get showsRequiredScreen =>
      _verdict == UpdateVerdict.required && _sessionSettled && (_signedIn || !_sentToSignIn);

  /// Told by main.dart whenever the session changes.
  void setSession({required bool signedIn, required bool settled}) {
    if (signedIn == _signedIn && settled == _sessionSettled) return;
    _signedIn = signedIn;
    _sessionSettled = settled;
    if (!signedIn) _sentToSignIn = false;
    notifyListeners();
  }

  /// OK on the login card.
  void okAtLogin() {
    _okAtLogin = true;
    notifyListeners();
  }

  /// Sign in on the required screen.
  void goToSignIn() {
    _sentToSignIn = true;
    notifyListeners();
  }

  void _onEnvChanged() {
    if (env.config.baseUrl == _baseUrl) return;
    _baseUrl = env.config.baseUrl;
    // A different server publishes its own releases.
    _info = null;
    _verdict = UpdateVerdict.none;
    _dismissed = false;
    _okAtLogin = false;
    _sentToSignIn = false;
    _phase = UpdatePhase.idle;
    _error = null;
    notifyListeners();
    check(force: true);
  }

  Future<void> check({bool force = false}) async {
    if (_checking) return;
    final last = _lastCheck;
    if (!force && last != null && _now().difference(last) < recheckAfter) return;
    _checking = true;
    final url = _baseUrl;
    try {
      final info = await apiFor(url).latest();
      if (url != _baseUrl) return; // the server was switched mid-check
      final before = _info?.latest?.versionCode;
      _info = info;
      _verdict = info.verdictFor(currentVersionCode);
      // "Later" lasts until something newer than what was dismissed is published.
      if (info.latest?.versionCode != before) {
        _dismissed = false;
        _okAtLogin = false;
      }
      notifyListeners();
    } catch (_) {
      // Silent on purpose — see the class comment.
    } finally {
      _lastCheck = _now();
      _checking = false;
    }
  }

  /// "Later" on the optional prompt.
  void dismiss() {
    if (_phase == UpdatePhase.downloading || _phase == UpdatePhase.installing) return;
    _dismissed = true;
    _phase = UpdatePhase.idle;
    _error = null;
    notifyListeners();
  }

  Future<void> startUpdate() async {
    final r = release;
    if (r == null || !_signedIn || _phase == UpdatePhase.downloading || _phase == UpdatePhase.installing) return;
    _error = null;
    try {
      if (!await installer.canInstall()) {
        _phase = UpdatePhase.needsPermission;
        notifyListeners();
        return;
      }
      final cached = _downloaded;
      if (cached == null || _downloadedCode != r.versionCode || !cached.existsSync()) {
        _phase = UpdatePhase.downloading;
        _progress = 0;
        notifyListeners();
        var lastShown = -1;
        final file = await apiFor(_baseUrl).download(r, onProgress: (p) {
          _progress = p;
          final percent = (p * 100).floor();
          if (percent != lastShown) {
            lastShown = percent;
            notifyListeners();
          }
        });
        _downloaded = file;
        _downloadedCode = r.versionCode;
      }
      _phase = UpdatePhase.installing;
      notifyListeners();
      await installer.install(_downloaded!.path);
      // Android's installer is on screen now. If the employee backs out of it, the
      // prompt is still there, and Update reuses the verified file.
      _phase = UpdatePhase.idle;
      notifyListeners();
    } on AppUpdateException catch (e) {
      _fail(e.message);
    } on ApiException catch (e) {
      _fail(e.message);
    } on PlatformException catch (_) {
      _fail('Android could not open the installer. Try again.');
    } catch (_) {
      _fail('The update could not be installed. Try again.');
    }
  }

  Future<void> openInstallSettings() => installer.openInstallSettings();

  /// Back in the app: continue an update that waited for the install permission,
  /// otherwise look for a new release (throttled).
  Future<void> onResumed() async {
    if (_phase == UpdatePhase.needsPermission) {
      await startUpdate();
      return;
    }
    await check();
  }

  void _fail(String message) {
    _phase = UpdatePhase.failed;
    _error = message;
    notifyListeners();
  }

  @override
  void dispose() {
    env.removeListener(_onEnvChanged);
    super.dispose();
  }
}
