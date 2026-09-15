import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../core/http/api_client.dart';
import '../../core/http/endpoints.dart';
import 'app_update_models.dart';

/// Where the update comes from. Tests pass a fake.
abstract class AppUpdateApi {
  Future<UpdateInfo> latest();

  /// Downloads [release] into the app's cache, checks its SHA-256, and returns the
  /// file. Throws [AppUpdateException] when it cannot be trusted or completed.
  Future<File> download(AppRelease release, {void Function(double progress)? onProgress});
}

class HttpAppUpdateApi implements AppUpdateApi {
  final String baseUrl;
  final String appVersion;
  final http.Client _client;
  final Future<Directory> Function() _cacheDir;

  HttpAppUpdateApi({
    required this.baseUrl,
    required this.appVersion,
    http.Client? client,
    Future<Directory> Function()? cacheDir,
  })  : _client = client ?? http.Client(),
        _cacheDir = cacheDir ?? getTemporaryDirectory;

  @override
  Future<UpdateInfo> latest() {
    // Public route: no token, so the check also works on the login screen.
    final api = ApiClient(baseUrl: baseUrl, tokenProvider: () async => null, appVersion: appVersion, client: _client);
    return api.get(Endpoints.appUpdateLatest, parse: (data) => UpdateInfo.fromJson(data as Map<String, dynamic>));
  }

  @override
  Future<File> download(AppRelease release, {void Function(double progress)? onProgress}) async {
    final sep = Platform.pathSeparator;
    final dir = Directory('${(await _cacheDir()).path}${sep}updates');
    // Only ever one downloaded update on the phone: clear what an earlier attempt left.
    if (dir.existsSync()) {
      for (final old in dir.listSync()) {
        _deleteQuietly(old);
      }
    } else {
      dir.createSync(recursive: true);
    }
    final file = File('${dir.path}${sep}hris-${release.versionName}+${release.versionCode}.apk');

    final request = http.Request('GET', Uri.parse('$baseUrl${release.downloadPath}'))
      ..headers['ngrok-skip-browser-warning'] = 'true'
      ..headers['User-Agent'] = 'HRISMobile/$appVersion (${Platform.operatingSystem})';

    final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(const Duration(seconds: 30));
    } on Object catch (e) {
      if (e is SocketException || e is http.ClientException || e is TimeoutException) {
        throw const AppUpdateException('Cannot reach the server to download the update. Check your connection.');
      }
      rethrow;
    }
    if (response.statusCode != 200) {
      throw AppUpdateException('The update could not be downloaded (error ${response.statusCode}).');
    }

    final total = response.contentLength ?? release.sizeBytes;
    final digest = _DigestSink();
    final hasher = sha256.startChunkedConversion(digest);
    final out = file.openWrite();
    var received = 0;
    try {
      // A minute with no bytes at all is a stalled download, not a slow one.
      await for (final chunk in response.stream.timeout(const Duration(seconds: 60))) {
        out.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call((received / total).clamp(0.0, 1.0));
      }
      await out.flush();
    } on Object catch (e) {
      await out.close();
      _deleteQuietly(file);
      if (e is SocketException || e is http.ClientException || e is TimeoutException) {
        throw const AppUpdateException('The download stopped. Check your connection and try again.');
      }
      rethrow;
    }
    await out.close();
    hasher.close();

    // The file is only handed to the installer if it is EXACTLY what was published.
    if (digest.value?.toString() != release.sha256) {
      _deleteQuietly(file);
      throw const AppUpdateException('The downloaded update was damaged. Try again.');
    }
    return file;
  }

  static void _deleteQuietly(FileSystemEntity entity) {
    try {
      entity.deleteSync(recursive: true);
    } catch (_) {
      // A leftover file is harmless; the next download clears the folder again.
    }
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
