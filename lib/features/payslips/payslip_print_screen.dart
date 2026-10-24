import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../shared/tokens.dart';
import 'payslip_api.dart';

/// "Print payslip" — the payslip EXACTLY as the website shows it on a phone
/// (user 2026-10-23): the web print page (`/employee/payslips/:id/print?app=1`,
/// the landscape A4 sheet scaled to fit) inside the app, printed through
/// Android's own print screen (print, or Save as PDF).
///
/// Sign-in: the web app reads its JWT from `localStorage['hris_token']`. The
/// webview first opens a tiny page of the SAME site (`/api/health`), writes the
/// app's session token into that site's storage, then opens the payslip page —
/// whose calls (`/api/auth/me`, `/api/me/payslips/:id[/breakdown]`) all accept
/// the mobile token. The webview's storage is its own; nothing reaches the
/// phone's browser.
///
/// Printing: Android prints a WebView through `PrintManager`; the native side
/// (`hris/print` in MainActivity) does that for this WebView's identifier.
class PayslipPrintScreen extends StatefulWidget {
  final int payslipId;
  final PayslipApi api;
  final String title;

  const PayslipPrintScreen({super.key, required this.payslipId, required this.api, this.title = 'Payslip'});

  @override
  State<PayslipPrintScreen> createState() => _PayslipPrintScreenState();
}

enum _Stage { resolving, signingIn, loadingPayslip, ready, failed }

class _PayslipPrintScreenState extends State<PayslipPrintScreen> {
  static const _printChannel = MethodChannel('hris/print');
  static const _failed = "Couldn't open the payslip. Check your connection and try again.";

  WebViewController? _web;
  PayslipPrintTarget? _target;
  _Stage _stage = _Stage.resolving;
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() => _stage = _Stage.resolving);
    try {
      final target = await widget.api.printTarget(widget.payslipId);
      if (!mounted) return;
      _target = target;
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(NavigationDelegate(
          onPageFinished: _onPageFinished,
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) setState(() => _stage = _Stage.failed);
          },
        ));
      setState(() {
        _web = controller;
        _stage = _Stage.signingIn;
      });
      // Step 1: any page of the same site, so its storage can take the token.
      await controller.loadRequest(target.url.replace(path: '/api/health', query: ''));
    } catch (_) {
      if (mounted) setState(() => _stage = _Stage.failed);
    }
  }

  Future<void> _onPageFinished(String url) async {
    final web = _web;
    final target = _target;
    if (web == null || target == null || !mounted) return;
    try {
      if (_stage == _Stage.signingIn) {
        final token = target.token ?? '';
        await web.runJavaScript("try { localStorage.setItem('hris_token', ${jsonEncode(token)}); } catch (e) {}");
        setState(() => _stage = _Stage.loadingPayslip);
        // Step 2: the payslip page itself, now signed in.
        await web.loadRequest(target.url);
      } else if (_stage == _Stage.loadingPayslip) {
        setState(() => _stage = _Stage.ready);
      }
    } catch (_) {
      if (mounted) setState(() => _stage = _Stage.failed);
    }
  }

  Future<void> _print() async {
    final web = _web;
    if (web == null || _printing) return;
    final platform = web.platform;
    if (platform is! AndroidWebViewController) {
      _say('Printing is not available on this phone.');
      return;
    }
    setState(() => _printing = true);
    try {
      await _printChannel.invokeMethod<bool>('printWebView', {
        'id': platform.webViewIdentifier,
        'name': widget.title.isEmpty ? 'Payslip' : 'Payslip ${widget.title}',
      });
    } on PlatformException catch (e) {
      _say(e.message ?? 'Printing is not available on this phone.');
    } on MissingPluginException {
      _say('Printing is not available on this phone.');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final web = _web;
    final ready = _stage == _Stage.ready;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Print',
            icon: const Icon(Icons.print_outlined),
            onPressed: ready && !_printing ? _print : null,
          ),
        ],
      ),
      body: _stage == _Stage.failed
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(HrisSpace.s4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_failed, textAlign: TextAlign.center, style: TextStyle(color: t.text2)),
                    const SizedBox(height: HrisSpace.s3),
                    OutlinedButton(onPressed: _start, child: const Text('Try again')),
                  ],
                ),
              ),
            )
          : Stack(
              children: [
                // Hidden until the payslip page itself has loaded — the sign-in
                // step's page is never shown.
                if (web != null) Offstage(offstage: !ready, child: WebViewWidget(controller: web)),
                if (!ready) const Center(child: CircularProgressIndicator()),
              ],
            ),
    );
  }
}
