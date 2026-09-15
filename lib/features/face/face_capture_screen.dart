import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/http/api_exception.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/message_banner.dart';
import 'face_asset_server.dart';
import 'face_models.dart';

/// How a capture attempt ended. Returned by [FaceCaptureScreen] through the
/// Navigator, so the caller gets either an embedding to submit or a reason.
sealed class FaceResult {
  const FaceResult();
}

class FaceCaptured extends FaceResult {
  final FaceCapture capture;
  const FaceCaptured(this.capture);
}

class FaceFailed extends FaceResult {
  final FaceFailure reason;

  /// Set when the SERVER refused to issue a challenge (e.g. the employee is not
  /// enrolled) — then the server's own sentence is better than ours.
  final String? serverMessage;
  const FaceFailed(this.reason, {this.serverMessage});
}

/// Issues the liveness challenge for one punch. Kept as a function type rather
/// than an API object so this screen has no opinion about HTTP — the clock's
/// api supplies it, and a test supplies a fake.
typedef ChallengeIssuer = Future<FaceChallenge> Function(String direction);

/// The face check that gates a mobile punch.
///
/// The capture itself runs in a WebView (see `assets/face/capture.html` for why:
/// the embedding must come from the same library and weights the website uses,
/// or it cannot be compared with the enrolled template). This screen owns the
/// things around it — the camera permission, the loopback asset server, the
/// challenge round-trip, and the honest reporting of what went wrong.
///
/// ORDER MATTERS: the model weights are ~13 MB and can take a while to load the
/// first time, while the server's challenge nonce is short-lived. So the engine
/// and the camera come up FIRST, and only then is the challenge requested —
/// that way the whole nonce lifetime is available for the liveness run instead
/// of being spent on a progress bar.
class FaceCaptureScreen extends StatefulWidget {
  final String direction; // 'in' | 'out' ('enroll' for a self-enrollment)
  final ChallengeIssuer issueChallenge;

  /// App-bar title; defaults to "Face check · Time In/Out".
  final String? title;

  /// Self-enrollment (server migration 061): the page also returns the JPEG of the
  /// exact frame the embedding came from, and waits for a frontal face to take it.
  final bool includeFrame;

  /// Injected by the widget tests, which cannot run a WebView.
  @visibleForTesting
  final Future<FaceResult> Function()? debugRunner;

  const FaceCaptureScreen({
    super.key,
    required this.direction,
    required this.issueChallenge,
    this.title,
    this.includeFrame = false,
    this.debugRunner,
  });

  @override
  State<FaceCaptureScreen> createState() => _FaceCaptureScreenState();
}

class _FaceCaptureScreenState extends State<FaceCaptureScreen> {
  final _server = FaceAssetServer();
  WebViewController? _web;
  String _stage = 'Checking the camera…';
  FaceFailure? _failure;
  String? _failureMessage;
  bool _finished = false;
  FaceChallenge? _challenge;
  Timer? _pageWatchdog;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  @override
  void dispose() {
    // Stop the camera inside the page before the WebView goes away, then drop
    // the loopback server. Neither may outlive this screen.
    _pageWatchdog?.cancel();
    _web?.runJavaScript('window.hrisStop && window.hrisStop()').catchError((_) {});
    unawaited(_server.stop());
    super.dispose();
  }

  void _finish(FaceResult result) {
    if (_finished || !mounted) return;
    _finished = true;
    Navigator.of(context).pop(result);
  }

  void _showFailure(FaceFailure reason, {String? message}) {
    if (_finished || !mounted) return;
    setState(() {
      _failure = reason;
      _failureMessage = message;
    });
  }

  Future<void> _run() async {
    // The tests cannot run a WebView; they hand the whole attempt back instead.
    final runner = widget.debugRunner;
    if (runner != null) {
      _finish(await runner());
      return;
    }

    // 1. The app-level camera permission. Granting the WebView's own request is
    //    not enough — Android checks the app's runtime grant underneath it.
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      _showFailure(FaceFailure.cameraDenied);
      return;
    }
    if (!mounted) return;

    // 2. The loopback origin (secure context + fetchable weights).
    setState(() => _stage = 'Loading the face model…');
    final String base;
    try {
      base = await _server.start();
    } catch (_) {
      _showFailure(FaceFailure.engineError);
      return;
    }

    // 3. The page. `hrisStart` is called once it reports itself loaded.
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0F172A))
      ..addJavaScriptChannel('HrisFace', onMessageReceived: _onPageMessage)
      // The page's console, forwarded so `adb logcat` can see which stage a
      // capture reached. It logs stages and backend choices only — never a
      // frame, a score or an embedding.
      ..setOnConsoleMessage((m) => debugPrint('[face-webview] ${m.message}'));
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      // getUserMedia starts playback without a tap, and the page's camera
      // request must be granted or it never sees a frame.
      await platform.setMediaPlaybackRequiresUserGesture(false);
      await platform.setOnPlatformPermissionRequest((request) => request.grant());
    }
    if (!mounted) return;
    setState(() => _web = controller);
    await controller.loadRequest(Uri.parse('$base/capture.html'));

    // A watchdog on the page itself. If the WebView never reports back, the
    // screen must say so rather than spin forever — which is exactly what it
    // did when the release build's network-security config was still blocking
    // the loopback origin and the page silently never loaded.
    _pageWatchdog = Timer(const Duration(seconds: 20), () {
      if (_challenge == null && !_finished) _showFailure(FaceFailure.engineError);
    });
  }

  /// Everything the capture page says comes through here as one JSON line.
  Future<void> _onPageMessage(JavaScriptMessage message) async {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(message.message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    switch (msg['type']) {
      case 'status':
        // 'loaded' = the page's script is alive: bring up the engine and the
        // camera. 'prepared' = both are up: only NOW ask for the challenge, so
        // the nonce is not spent waiting for 13 MB of weights. (Until Sep 14 the
        // challenge was requested on 'loaded', before the weights, and slow
        // phones expired mid-punch.)
        _pageWatchdog?.cancel();
        if (msg['state'] == 'loaded') await _web?.runJavaScript('window.hrisPrepare()');
        if (msg['state'] == 'prepared') await _issueAndStart();
        // The page reports each stage it reaches, so the employee sees progress
        // instead of one unchanging line while 13 MB of weights load.
        if (msg['state'] == 'stage' && mounted) {
          setState(() => _stage = (msg['stage'] as String?) ?? _stage);
        }
        if (msg['state'] == 'ready' && mounted) setState(() => _stage = '');
      case 'result':
        if (msg['ok'] == true) {
          _onCaptured(msg);
        } else {
          _showFailure(faceFailureFromCode(msg['reason'] as String?));
        }
    }
  }

  Future<void> _issueAndStart() async {
    if (!mounted || _challenge != null) return;
    setState(() => _stage = 'Asking the server for a challenge…');
    FaceChallenge challenge;
    try {
      challenge = await widget.issueChallenge(widget.direction);
    } on ApiException catch (e) {
      // A refusal here is usually meaningful (not enrolled, switch revoked) —
      // carry the server's own words rather than a generic engine error.
      _showFailure(FaceFailure.engineError, message: e.message);
      return;
    } catch (_) {
      _showFailure(FaceFailure.engineError);
      return;
    }
    if (!challenge.isUsable) {
      _showFailure(FaceFailure.noChallenge);
      return;
    }
    _challenge = challenge;
    if (!mounted) return;
    setState(() => _stage = 'Get ready…');
    // The server's ORDER, passed through untouched — the backend verifies the
    // response against the sequence it issued.
    await _web?.runJavaScript(
      'window.hrisStart(${jsonEncode(challenge.actions)}, ${jsonEncode({'includeFrame': widget.includeFrame})})',
    );
  }

  void _onCaptured(Map<String, dynamic> msg) {
    final raw = (msg['embedding'] as List?) ?? const [];
    final capture = FaceCapture(
      nonce: _challenge?.nonce ?? '',
      embedding: raw.map((e) => (e as num).toDouble()).toList(growable: false),
      dims: (msg['dims'] as num?)?.toInt() ?? raw.length,
      modelVersion: (msg['modelVersion'] ?? 'human-3') as String,
      completedChallenges: ((msg['completed'] as List?) ?? const []).map((e) => '$e').toList(growable: false),
      photoJpegBase64: msg['photo'] as String?,
    );
    // An enrollment without its photo cannot be reviewed, so it is not usable.
    if (!capture.isUsable || capture.nonce.isEmpty || (widget.includeFrame && !capture.hasPhoto)) {
      _showFailure(FaceFailure.noEmbedding);
      return;
    }
    _finish(FaceCaptured(capture));
  }

  Future<void> _retry() async {
    _pageWatchdog?.cancel();
    setState(() {
      _failure = null;
      _failureMessage = null;
      _challenge = null;
      _web = null;
      _stage = 'Checking the camera…';
    });
    await _server.stop();
    await _run();
  }

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final label = widget.direction == 'in' ? 'Time In' : 'Time Out';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        // Backing out is a cancel, never a silent punch.
        if (!didPop) _finish(const FaceFailed(FaceFailure.cancelled));
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        appBar: AppBar(
          title: Text(widget.title ?? 'Face check · $label'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => _finish(const FaceFailed(FaceFailure.cancelled)),
          ),
        ),
        body: _failure != null
            ? _FailurePanel(
                message: _failureMessage ?? faceFailureMessage(_failure!),
                onRetry: _retry,
                onCancel: () => _finish(FaceFailed(_failure!)),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  if (_web != null) WebViewWidget(controller: _web!),
                  if (_stage.isNotEmpty)
                    ColoredBox(
                      color: const Color(0xFF0F172A),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: HrisSpace.s4),
                            Text(
                              _stage,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: HrisType.sm, height: 1.5, color: t.muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _FailurePanel extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  const _FailurePanel({required this.message, required this.onRetry, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(HrisSpace.s4),
        child: AppCard(
          tone: AppCardTone.danger,
          maxWidth: 440,
          centered: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MessageBanner.error(message),
              const SizedBox(height: HrisSpace.s3),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
              const SizedBox(height: HrisSpace.s2),
              OutlinedButton(onPressed: onCancel, child: const Text('Cancel')),
            ],
          ),
        ),
      ),
    );
  }
}
