/// The liveness challenge the SERVER issued for one punch.
///
/// The nonce is single-use and short-lived, and `actions` is an ORDERED,
/// randomized sequence. The client must run them in exactly that order and echo
/// them back: the server verifies the response against the challenge it issued,
/// so a pre-recorded attempt cannot have known the sequence in advance and a
/// reordered one fails closed. Never shuffle this list on the phone.
class FaceChallenge {
  final String nonce;
  final List<String> actions;

  const FaceChallenge({required this.nonce, required this.actions});

  factory FaceChallenge.fromJson(Map<String, dynamic> j) => FaceChallenge(
        nonce: (j['nonce'] ?? '') as String,
        actions: ((j['challenge_types'] as List?) ?? const []).map((e) => '$e').toList(growable: false),
      );

  bool get isUsable => nonce.length == 64 && actions.isNotEmpty;
}

/// What the capture surface produced: the embedding to submit, plus the nonce
/// and the actions it was produced under.
///
/// The embedding is L2-normalized `human-3` output — the same vector the website
/// sends — and is never logged, never stored on the device, and never leaves
/// this object except in the punch request body.
class FaceCapture {
  final String nonce;
  final List<double> embedding;
  final int dims;
  final String modelVersion;
  final List<String> completedChallenges;

  /// ENROLLMENT ONLY (server migration 061): base64 JPEG of the exact frame the
  /// embedding was computed from, so HR can compare it with the employee before
  /// approving. Null on a punch. Like the embedding, it is biometric data: never
  /// logged, never cached on the device, sent only in the enrollment request.
  final String? photoJpegBase64;

  const FaceCapture({
    required this.nonce,
    required this.embedding,
    required this.dims,
    required this.modelVersion,
    required this.completedChallenges,
    this.photoJpegBase64,
  });

  /// ~512 KB decoded — the server's cap; anything larger is refused on-device.
  static const maxPhotoBase64Length = 700000;

  bool get hasPhoto =>
      photoJpegBase64 != null && photoJpegBase64!.isNotEmpty && photoJpegBase64!.length <= maxPhotoBase64Length;

  /// The body of `POST /api/me/face-enrollment`: the same challenge answer as a
  /// punch, plus explicit consent and the photo.
  Map<String, dynamic> toEnrollmentJson() => {
        'nonce': nonce,
        'embedding': embedding,
        'liveness_passed': true,
        'completed_challenges': completedChallenges,
        'model_version': modelVersion,
        'consent_given': true,
        'photo': {'type': 'image/jpeg', 'data': photoJpegBase64},
      };

  /// The bounds the server enforces (`EMBEDDING_MIN_DIMS`/`MAX_DIMS`), asserted
  /// on-device so a mis-sized capture fails here instead of round-tripping to a
  /// 422 with the user standing there.
  bool get isUsable =>
      embedding.length >= 64 &&
      embedding.length <= 2048 &&
      embedding.every((v) => v.isFinite) &&
      completedChallenges.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'nonce': nonce,
        'embedding': embedding,
        'liveness_passed': true,
        'completed_challenges': completedChallenges,
        'model_version': modelVersion,
      };

  /// Deliberately says nothing about the vector or the photo: both are biometric
  /// data and must never reach a log line or a crash report.
  @override
  String toString() => 'FaceCapture($modelVersion, $dims dims, ${completedChallenges.join("+")})';
}

/// Why a capture attempt ended without an embedding. The reasons come from the
/// capture page; each maps to a sentence the employee can act on.
enum FaceFailure {
  cameraDenied,
  noCamera,
  cameraError,
  timeout,
  noEmbedding,
  noChallenge,
  engineError,
  cancelled,
}

FaceFailure faceFailureFromCode(String? code) => switch (code) {
      'camera_denied' => FaceFailure.cameraDenied,
      'no_camera' => FaceFailure.noCamera,
      'camera_error' => FaceFailure.cameraError,
      'timeout' => FaceFailure.timeout,
      'no_embedding' => FaceFailure.noEmbedding,
      'no_challenge' => FaceFailure.noChallenge,
      _ => FaceFailure.engineError,
    };

String faceFailureMessage(FaceFailure reason) => switch (reason) {
      FaceFailure.cameraDenied =>
        'Camera access is off, so your face cannot be checked. Allow the camera in Settings, then try again.',
      FaceFailure.noCamera => 'This phone has no front camera the app can use.',
      FaceFailure.cameraError => 'The camera could not start. Close any other app using it and try again.',
      FaceFailure.timeout => 'That took too long. Follow the prompt as it appears and try again.',
      FaceFailure.noEmbedding => "Couldn't read your face clearly. Move into better light and try again.",
      FaceFailure.noChallenge => 'The server did not issue a liveness challenge. Try again.',
      FaceFailure.engineError => 'Something went wrong during the face check. Please try again.',
      FaceFailure.cancelled => 'Face check cancelled — nothing was recorded.',
    };
