import 'dart:convert';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/auth/session_controller.dart';
import '../../core/http/endpoints.dart';
import 'profile_photo_models.dart';

/// The server calls behind changing my profile photo (server migration 062).
/// Abstract so the screen is tested against a scripted fake.
abstract class ProfilePhotoApi {
  /// My current photo and where the last one I sent stands.
  Future<ProfilePhotoState> state();

  /// Send one JPEG for HR to review. Returns where I stand afterwards (pending).
  Future<ProfilePhotoState> submit(Uint8List jpeg);
}

/// The real thing: the mobile-only endpoint, through the session's guard so a revoked
/// switch or an expired token signs the phone out in one place.
class MobileProfilePhotoApi implements ProfilePhotoApi {
  final SessionController session;

  const MobileProfilePhotoApi(this.session);

  @override
  Future<ProfilePhotoState> state() => session.guard(() => session.client.get(
        Endpoints.profilePhoto,
        parse: (d) => ProfilePhotoState.fromJson(d as Map<String, dynamic>?),
      ));

  @override
  Future<ProfilePhotoState> submit(Uint8List jpeg) => session.guard(() => session.client.post(
        Endpoints.profilePhoto,
        body: {
          'photo': {'type': 'image/jpeg', 'data': base64Encode(jpeg)},
        },
        parse: (d) => ProfilePhotoState.fromJson(d as Map<String, dynamic>?),
      ));
}

/// Takes one photo. Null when the person backed out of the camera. The widget tests
/// pass a fake — they cannot open a camera.
typedef PhotoTaker = Future<Uint8List?> Function();

/// The camera refused: Android's runtime permission is not granted.
class CameraPermissionDenied implements Exception {
  const CameraPermissionDenied();
}

/// CAMERA ONLY (user's decision 2026-09-15): no gallery, so the photo is taken now,
/// by whoever holds the phone. Front camera first (a selfie); capped at 1080 px and
/// JPEG quality 85, which keeps an upload to a few hundred KB.
Future<Uint8List?> takeProfilePhotoWithCamera() async {
  final status = await Permission.camera.request();
  if (!status.isGranted) throw const CameraPermissionDenied();
  final file = await ImagePicker().pickImage(
    source: ImageSource.camera,
    preferredCameraDevice: CameraDevice.front,
    maxWidth: 1080,
    maxHeight: 1080,
    imageQuality: 85,
    requestFullMetadata: false,
  );
  if (file == null) return null;
  return file.readAsBytes();
}

/// JPEG starts FF D8 FF — the server checks the same bytes.
bool looksLikeJpeg(Uint8List bytes) =>
    bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
