import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../shared/tokens.dart';
import '../../shared/widgets/app_card.dart';
import 'app_update_controller.dart';
import 'app_update_models.dart';

/// Sits ABOVE every screen (MaterialApp.builder), so the update prompt reaches the
/// employee wherever they are — the login screen included.
///
///   - a REQUIRED update replaces the whole app with [_UpdateRequiredScreen];
///   - an AVAILABLE update is a card at the bottom: Later / Update.
///
/// With no [AppUpdateController] provided (widget tests) it is just [child].
class UpdateGate extends StatefulWidget {
  final Widget child;

  const UpdateGate({super.key, required this.child});

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppUpdateController?>()?.check(force: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<AppUpdateController?>()?.onResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppUpdateController?>();
    if (c == null) return widget.child;
    if (c.verdict == UpdateVerdict.required && c.release != null) {
      return _UpdateRequiredScreen(controller: c);
    }
    return Stack(
      children: [
        widget.child,
        if (c.showsPrompt && c.release != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(HrisSpace.s3),
                child: Material(
                  type: MaterialType.transparency,
                  child: AppCard(child: _UpdateBody(controller: c, required: false)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _UpdateRequiredScreen extends StatelessWidget {
  final AppUpdateController controller;

  const _UpdateRequiredScreen({required this.controller});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(HrisSpace.s4),
            child: AppCard(
              maxWidth: 440,
              padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s5, vertical: HrisSpace.s6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.system_update_outlined, size: 40, color: t.primary),
                  const SizedBox(height: HrisSpace.s3),
                  _UpdateBody(controller: controller, required: true),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The words and buttons for every phase, shared by the card and the full screen.
class _UpdateBody extends StatelessWidget {
  final AppUpdateController controller;
  final bool required;

  const _UpdateBody({required this.controller, required this.required});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final r = controller.release!;
    final titleStyle = TextStyle(fontSize: HrisType.md, fontWeight: HrisType.semibold, color: t.text);
    final bodyStyle = TextStyle(fontSize: HrisType.sm, height: 1.45, color: t.muted);

    final (String title, String body) = switch (controller.phase) {
      UpdatePhase.downloading => (
          'Downloading the update… ${(controller.progress * 100).floor()}%',
          'Version ${r.versionName} (${r.sizeLabel}). Keep the app open until the installer appears.',
        ),
      UpdatePhase.installing => ('Opening the installer…', 'Tap Update (or Install) on the screen Android shows next.'),
      UpdatePhase.needsPermission => (
          'Allow HRIS to install its updates',
          'Android asks this once. Turn on "Allow from this source" for HRIS, then come back to the app.',
        ),
      UpdatePhase.failed => ('The update did not finish', controller.error ?? 'Try again.'),
      UpdatePhase.idle => required
          ? (
              'Update required',
              'This version of HRIS (${controller.currentVersionName}) is no longer supported. '
                  'Install version ${r.versionName} (${r.sizeLabel}) to keep using the app.',
            )
          : ('Update available', 'Version ${r.versionName} is ready to install (${r.sizeLabel}).'),
    };

    final busy = controller.phase == UpdatePhase.downloading || controller.phase == UpdatePhase.installing;
    final notes = r.notes;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: titleStyle, textAlign: required ? TextAlign.center : TextAlign.start),
        const SizedBox(height: HrisSpace.s1),
        Text(body, style: bodyStyle, textAlign: required ? TextAlign.center : TextAlign.start),
        if (notes != null && notes.isNotEmpty && controller.phase == UpdatePhase.idle) ...[
          const SizedBox(height: HrisSpace.s2),
          Text("What's new: $notes", style: bodyStyle, maxLines: 4, overflow: TextOverflow.ellipsis),
        ],
        if (controller.phase == UpdatePhase.downloading) ...[
          const SizedBox(height: HrisSpace.s3),
          LinearProgressIndicator(value: controller.progress > 0 ? controller.progress : null),
        ],
        if (!busy) ...[
          const SizedBox(height: HrisSpace.s3),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!required)
                TextButton(onPressed: controller.dismiss, child: const Text('Later')),
              const SizedBox(width: HrisSpace.s2),
              if (controller.phase == UpdatePhase.needsPermission)
                FilledButton(onPressed: controller.openInstallSettings, child: const Text('Open settings'))
              else
                FilledButton(
                  onPressed: controller.startUpdate,
                  child: Text(controller.phase == UpdatePhase.failed ? 'Try again' : (required ? 'Update now' : 'Update')),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
