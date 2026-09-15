import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/http/api_exception.dart';
import '../../core/time/manila_time.dart';
import '../../shared/button_styles.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/message_banner.dart';
import 'profile_photo_api.dart';
import 'profile_photo_models.dart';

/// My profile photo (server migration 062): the photo HR has on file, where the last
/// one I sent stands, and — camera only — a new one to send.
///
/// Nothing changes until HR approves (user's decision 2026-09-15): the profile photo is
/// what HR compares a phone face enrollment against, so the screen always says the
/// current photo stays until then. A rejection shows HR's reason. Whether "Take a new
/// photo" is offered follows the `profile_photo:create` grant; the server checks it
/// again.
class ProfilePhotoScreen extends StatefulWidget {
  final ProfilePhotoApi api;

  /// The environment's base URL — the photo path from the server is relative to it.
  final String baseUrl;

  /// The login holds `profile_photo:create`.
  final bool canSend;

  /// Replaces the real camera. Only the widget tests pass this.
  @visibleForTesting
  final PhotoTaker? takePhotoOverride;

  const ProfilePhotoScreen({
    super.key,
    required this.api,
    required this.baseUrl,
    required this.canSend,
    this.takePhotoOverride,
  });

  @override
  State<ProfilePhotoScreen> createState() => _ProfilePhotoScreenState();
}

class _ProfilePhotoScreenState extends State<ProfilePhotoScreen> {
  ProfilePhotoState? _state;
  bool _loading = true;
  String? _loadError;

  /// A photo just taken, waiting for "Send to HR" or "Retake".
  Uint8List? _preview;
  bool _sending = false;
  String? _error;
  bool _cameraDenied = false;
  bool _justSent = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final state = await widget.api.state();
      if (!mounted) return;
      setState(() {
        _state = state;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _take() async {
    setState(() {
      _error = null;
      _cameraDenied = false;
      _justSent = false;
    });
    try {
      final bytes = await (widget.takePhotoOverride ?? takeProfilePhotoWithCamera)();
      if (!mounted || bytes == null) return; // backed out of the camera
      if (!looksLikeJpeg(bytes)) {
        setState(() => _error = "The camera returned a picture this app can't send. Try again.");
        return;
      }
      setState(() => _preview = bytes);
    } on CameraPermissionDenied {
      if (!mounted) return;
      setState(() => _cameraDenied = true);
    }
  }

  Future<void> _send() async {
    final photo = _preview;
    if (photo == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final state = await widget.api.submit(photo);
      if (!mounted) return;
      setState(() {
        _state = state;
        _preview = null;
        _sending = false;
        _justSent = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.status == 403
            ? 'Changing your profile photo from the app is turned off for your account. Ask HR.'
            : e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    if (_loading && _state == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null && _state == null) {
      return ListView(
        padding: const EdgeInsets.all(HrisSpace.s4),
        children: [
          MessageBanner.error(_loadError!),
          const SizedBox(height: HrisSpace.s3),
          OutlinedButton(onPressed: _load, child: const Text('Try again')),
        ],
      );
    }

    final state = _state ?? ProfilePhotoState.empty;
    final preview = _preview;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(HrisSpace.s4),
        children: [
          AppCard(
            child: Column(
              children: [
                _PhotoCircle(
                  memory: preview,
                  url: preview == null && state.profileImageUrl != null ? '${widget.baseUrl}${state.profileImageUrl}' : null,
                ),
                const SizedBox(height: HrisSpace.s3),
                Text(
                  preview != null
                      ? 'Your new photo'
                      : state.profileImageUrl != null
                          ? 'Your profile photo'
                          : 'No profile photo yet',
                  style: TextStyle(fontSize: HrisType.md, fontWeight: HrisType.semibold, color: t.text),
                ),
                if (preview != null) ...[
                  const SizedBox(height: HrisSpace.s1),
                  Text(
                    'HR checks it before it replaces your current photo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: HrisType.xs, color: t.muted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: HrisSpace.s4),
          ..._banners(state),
          if (_error != null) ...[MessageBanner.error(_error!), const SizedBox(height: HrisSpace.s3)],
          if (_cameraDenied) ...[
            const MessageBanner.warning(
              'The camera is not allowed for HRIS. Allow it in Android settings to take a photo.',
            ),
            const SizedBox(height: HrisSpace.s2),
            OutlinedButton(onPressed: openAppSettings, child: const Text('Open settings')),
            const SizedBox(height: HrisSpace.s3),
          ],
          if (!widget.canSend)
            Text(
              'Changing your profile photo from the app is turned off for your account. Ask HR if you need a new one.',
              style: TextStyle(fontSize: HrisType.sm, color: t.muted),
            )
          else if (preview != null) ...[
            FilledButton(
              onPressed: _sending ? null : _send,
              style: HrisButtonStyles.primaryLg(context),
              child: Text(_sending ? 'Sending…' : 'Send to HR'),
            ),
            const SizedBox(height: HrisSpace.s2),
            OutlinedButton(
              onPressed: _sending ? null : _take,
              style: HrisButtonStyles.secondary(context),
              child: const Text('Retake'),
            ),
            TextButton(
              onPressed: _sending ? null : () => setState(() => _preview = null),
              child: const Text('Cancel'),
            ),
          ] else ...[
            FilledButton.icon(
              onPressed: _take,
              style: HrisButtonStyles.primaryLg(context),
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(state.phase == ProfilePhotoPhase.pending ? 'Take another photo' : 'Take a new photo'),
            ),
            const SizedBox(height: HrisSpace.s2),
            Text(
              state.phase == ProfilePhotoPhase.pending
                  ? 'A new photo replaces the one waiting for HR.'
                  : 'Uses the camera. HR checks the photo before it replaces your current one.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: HrisType.xs, color: t.muted),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _banners(ProfilePhotoState state) {
    final gap = const SizedBox(height: HrisSpace.s3);
    if (_preview != null) return const [];
    switch (state.phase) {
      case ProfilePhotoPhase.pending:
        final sent = state.submittedAt == null ? '' : ' Sent ${ManilaTime.dateTime(state.submittedAt!)}.';
        return [
          MessageBanner.info(
            '${_justSent ? 'Sent. ' : ''}Your new photo is waiting for HR to approve it.$sent '
            'Your current photo stays until then.',
          ),
          gap,
        ];
      case ProfilePhotoPhase.rejected:
        return [
          MessageBanner.warning(
            'Your last photo was not approved.\nReason: ${state.reason?.trim().isNotEmpty == true ? state.reason : '—'}',
          ),
          gap,
        ];
      case ProfilePhotoPhase.approved:
        final reviewed = state.reviewedAt;
        // A recent approval is news; an old one is just the photo above.
        if (reviewed == null || DateTime.now().toUtc().difference(reviewed).inDays > 7) return const [];
        return [MessageBanner.success('Your new photo was approved ${ManilaTime.dateTime(reviewed)}.'), gap];
      case ProfilePhotoPhase.none:
        return const [];
    }
  }
}

/// The photo in a circle: the one just taken, the one on the server, or a placeholder.
class _PhotoCircle extends StatelessWidget {
  final Uint8List? memory;
  final String? url;

  const _PhotoCircle({this.memory, this.url});

  static const _size = 160.0;

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final placeholder = Container(
      color: t.primarySoft,
      alignment: Alignment.center,
      child: Icon(Icons.person_outline, size: 72, color: t.primary),
    );
    Widget image = placeholder;
    if (memory != null) {
      // A capture the phone cannot decode shows the placeholder rather than an error.
      image = Image.memory(
        memory!,
        fit: BoxFit.cover,
        width: _size,
        height: _size,
        errorBuilder: (_, _, _) => placeholder,
      );
    } else if (url != null) {
      image = Image.network(
        url!,
        fit: BoxFit.cover,
        width: _size,
        height: _size,
        // The sandbox runs behind ngrok, which otherwise answers with its warning page.
        headers: const {'ngrok-skip-browser-warning': 'true'},
        errorBuilder: (_, _, _) => placeholder,
      );
    }
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: t.border, width: 2)),
      clipBehavior: Clip.antiAlias,
      child: image,
    );
  }
}
