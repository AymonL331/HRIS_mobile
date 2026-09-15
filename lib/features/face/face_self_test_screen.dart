import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../shared/tokens.dart';
import '../../shared/widgets/app_card.dart';
import 'face_asset_server.dart';

/// What `hrisSelfTest()` in `assets/face/capture.html` reports.
class FaceSelfTestReport {
  final int filesChecked;
  final List<String> badFiles;
  final double? distance;
  final String? backend;
  final String gpu;
  final String userAgent;
  final String? error;

  const FaceSelfTestReport({
    required this.filesChecked,
    required this.badFiles,
    required this.distance,
    required this.backend,
    required this.gpu,
    required this.userAgent,
    required this.error,
  });

  factory FaceSelfTestReport.fromJson(Map<String, dynamic> j) => FaceSelfTestReport(
        filesChecked: (j['filesChecked'] as num?)?.toInt() ?? 0,
        badFiles: ((j['badFiles'] as List?) ?? const []).map((e) => '$e').toList(growable: false),
        distance: (j['distance'] as num?)?.toDouble(),
        backend: j['backend'] as String?,
        gpu: (j['gpu'] ?? 'unknown') as String,
        userAgent: (j['userAgent'] ?? '') as String,
        error: j['error'] as String?,
      );

  /// A correct engine reproduces the desktop reference to ~1e-5; anything past
  /// 0.05 is not rounding, it is a different computation.
  static const maxHealthyDistance = 0.05;

  bool get filesOk => filesChecked > 0 && badFiles.isEmpty;
  bool get engineOk => distance != null && distance! <= maxHealthyDistance;
  bool get healthy => error == null && filesOk && engineOk;

  /// "Chrome/133.0.6943.137" out of the WebView's user agent.
  String get webViewVersion => RegExp(r'Chrome/[\d.]+').firstMatch(userAgent)?.group(0) ?? 'unknown';
}

/// Sandbox diagnostics: is the face engine INSIDE this app computing correct
/// fingerprints on this phone? Needs no camera, no face and no punch.
///
/// Built for the Sep 14 field test, where three Mali-G57 phones produced
/// fingerprints ~1.3 away from the enrolled face in the app while the very same
/// engine, weights and steps were correct in the phone's own Chrome. A phone
/// that passes this but still fails a real face is being handed bad camera
/// frames by its WebView; one that fails it has broken weights or a broken engine.
class FaceSelfTestScreen extends StatefulWidget {
  const FaceSelfTestScreen({super.key});

  @override
  State<FaceSelfTestScreen> createState() => _FaceSelfTestScreenState();
}

class _FaceSelfTestScreenState extends State<FaceSelfTestScreen> {
  final _server = FaceAssetServer();
  WebViewController? _web;
  String _stage = 'Starting…';
  FaceSelfTestReport? _report;
  String? _failure;
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    unawaited(_server.stop());
    super.dispose();
  }

  Future<void> _run() async {
    final String base;
    try {
      base = await _server.start();
    } catch (e) {
      setState(() => _failure = 'The in-app file server did not start: $e');
      return;
    }
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0F172A))
      ..addJavaScriptChannel('HrisFace', onMessageReceived: _onMessage)
      ..setOnConsoleMessage((m) => debugPrint('[face-selftest] ${m.message}'))
      // A page that never loads posts no message at all, so without this the
      // screen could only say "timed out". Name the actual failure instead.
      ..setNavigationDelegate(NavigationDelegate(
        onWebResourceError: (e) {
          if (!mounted || _report != null) return;
          setState(() => _failure = 'The page failed to load ${e.url ?? ''}: ${e.errorType?.name ?? ''} ${e.errorCode} ${e.description}');
        },
        onHttpError: (e) {
          if (!mounted || _report != null) return;
          setState(() => _failure = 'HTTP ${e.response?.statusCode} for ${e.request?.uri}');
        },
      ));
    if (!mounted) return;
    setState(() => _web = controller);
    await controller.loadRequest(Uri.parse('$base/capture.html'));
    // Weights + warm-up can take a minute on a slow phone; never spin forever.
    _watchdog = Timer(const Duration(seconds: 150), () {
      if (_report == null && mounted) setState(() => _failure = 'The self-check did not finish within 150 seconds.');
    });
  }

  Future<void> _onMessage(JavaScriptMessage message) async {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(message.message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (!mounted) return;
    switch (msg['type']) {
      case 'status':
        if (msg['state'] == 'loaded') await _web?.runJavaScript('window.hrisSelfTest()');
        if (msg['state'] == 'stage') setState(() => _stage = (msg['stage'] as String?) ?? _stage);
      case 'selftest':
        _watchdog?.cancel();
        setState(() {
          _report = FaceSelfTestReport.fromJson(msg);
          _web = null; // the engine's job is done; drop the WebView
        });
        unawaited(_server.stop());
    }
  }

  Future<void> _again() async {
    _watchdog?.cancel();
    await _server.stop();
    setState(() {
      _report = null;
      _failure = null;
      _web = null;
      _stage = 'Starting…';
    });
    await _run();
  }

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('Face engine self-check')),
      body: report != null || _failure != null
          ? _Results(report: report, failure: _failure, onAgain: _again)
          : Stack(
              fit: StackFit.expand,
              children: [
                // The WebView must be on screen for its WebGL context to run.
                if (_web != null) WebViewWidget(controller: _web!),
                ColoredBox(
                  color: t.bg,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: HrisSpace.s4),
                        Text(_stage, textAlign: TextAlign.center, style: TextStyle(color: t.muted)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Results extends StatelessWidget {
  final FaceSelfTestReport? report;
  final String? failure;
  final Future<void> Function() onAgain;

  const _Results({required this.report, required this.failure, required this.onAgain});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final r = report;

    final (String headline, String detail, AppCardTone tone) = switch (r) {
      null => ('The self-check could not run', failure ?? 'Unknown error.', AppCardTone.danger),
      _ when r.error != null => ('The self-check hit an error', r.error!, AppCardTone.danger),
      _ when !r.filesOk => (
          'Model files are damaged inside this app',
          'The face model files the app serves do not match the website\'s. Fingerprints computed from them are wrong.',
          AppCardTone.danger,
        ),
      _ when !r.engineOk => (
          'The face engine computes wrong fingerprints here',
          'The files are intact, but the built-in test face does not reproduce its reference fingerprint.',
          AppCardTone.danger,
        ),
      _ => (
          'The face engine in this app is correct',
          'Files intact and the test face reproduces its reference. If clocking in still fails on this phone, '
              'the camera frames the app receives are the problem.',
          AppCardTone.surface,
        ),
    };

    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: HrisSpace.s2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 132, child: Text(label, style: TextStyle(color: t.muted))),
              Expanded(child: SelectableText(value, style: const TextStyle(fontFamily: 'monospace'))),
            ],
          ),
        );

    return ListView(
      padding: const EdgeInsets.all(HrisSpace.s4),
      children: [
        AppCard(
          tone: tone,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(headline, style: const TextStyle(fontSize: HrisType.lg, fontWeight: FontWeight.w600)),
              const SizedBox(height: HrisSpace.s2),
              Text(detail),
            ],
          ),
        ),
        if (r != null) ...[
          const SizedBox(height: HrisSpace.s3),
          AppCard(
            child: Column(
              children: [
                row('Model files', r.badFiles.isEmpty ? '${r.filesChecked} of ${r.filesChecked} match' : 'DAMAGED: ${r.badFiles.join(', ')}'),
                row('Test face distance', r.distance == null ? '—' : r.distance!.toStringAsExponential(2)),
                row('Engine', r.backend ?? '—'),
                row('GPU', r.gpu),
                row('WebView', r.webViewVersion),
              ],
            ),
          ),
        ],
        const SizedBox(height: HrisSpace.s4),
        FilledButton(onPressed: onAgain, child: const Text('Run again')),
      ],
    );
  }
}
