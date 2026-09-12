import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Serves the bundled face-capture page and its model weights over loopback
/// HTTP, so the WebView loads them from `http://127.0.0.1:<port>/` instead of
/// `file://`.
///
/// That indirection is not decoration — two things depend on it:
///
///   1. `getUserMedia` only runs in a SECURE CONTEXT. Loopback counts as
///      potentially trustworthy, so the camera works without shipping a
///      certificate or relaxing WebView security.
///   2. Human loads its weights with `fetch()`. From a `file://` document those
///      requests are blocked unless the WebView is opened up with
///      `allowFileAccessFromFileURLs`, which is a setting worth not turning on
///      in an app that handles biometrics.
///
/// It binds to the loopback interface ONLY, on an ephemeral port, and serves
/// nothing but the three asset paths below — it is not reachable from the
/// network and cannot be pointed at anything else on the device.
class FaceAssetServer {
  static const _root = 'assets/face';

  /// The files this server will serve, and nothing else. An allowlist rather
  /// than a path join: a request can never walk out of the asset bundle.
  static const _allowed = <String>{'capture.html', 'human.js'};

  HttpServer? _server;
  final Map<String, Uint8List> _cache = {};

  /// The base URL to load, e.g. `http://127.0.0.1:53124`. Null until [start].
  String? get baseUrl => _server == null ? null : 'http://127.0.0.1:${_server!.port}';

  Future<String> start() async {
    if (_server != null) return baseUrl!;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0, shared: false);
    _server = server;
    unawaited(_serve(server));
    return baseUrl!;
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      try {
        await _respond(request);
      } catch (_) {
        // A dead socket (the screen closed mid-load) must not take the server
        // down — the next request is served normally.
      }
    }
  }

  Future<void> _respond(HttpRequest request) async {
    final path = request.uri.path.replaceFirst(RegExp(r'^/'), '');
    final name = path.isEmpty ? 'capture.html' : path;

    final isModel = name.startsWith('models/') && !name.contains('..');
    if (!_allowed.contains(name) && !isModel) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    late final Uint8List bytes;
    try {
      bytes = _cache[name] ??= (await rootBundle.load('$_root/$name')).buffer.asUint8List();
    } catch (_) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    request.response.headers
      ..contentType = _typeFor(name)
      // The weights never change within a build, and Human re-requests them on
      // every page load; caching keeps a retry from re-reading 13 MB.
      ..set(HttpHeaders.cacheControlHeader, 'public, max-age=86400');
    request.response.add(bytes);
    await request.response.close();
  }

  static ContentType _typeFor(String name) {
    if (name.endsWith('.html')) return ContentType.html;
    if (name.endsWith('.js')) return ContentType('application', 'javascript', charset: 'utf-8');
    if (name.endsWith('.json')) return ContentType.json;
    return ContentType.binary; // the .bin weight shards
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _cache.clear();
    await server?.close(force: true);
  }
}
