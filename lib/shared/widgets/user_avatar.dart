import 'package:flutter/material.dart';

import '../tokens.dart';

/// The web top-bar avatar (Topbar.module.css .avatar): a 32px circle carrying the
/// account's PROFILE PHOTO when there is one, else its first initial on the primary
/// colour — the same fallback order as the website's Avatar (2026-09-16: an
/// approved photo was invisible in the app because this only ever drew the letter).
///
/// The photo is a server PATH (`/api/uploads/...`), so it needs the environment's
/// [baseUrl]; without one, or if the image cannot be fetched, the initial stands in.
class UserAvatar extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final String? baseUrl;

  const UserAvatar(this.name, {super.key, this.imageUrl, this.baseUrl});

  String get initial {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final letter = Container(
      width: HrisSize.avatar,
      height: HrisSize.avatar,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: t.primary, shape: BoxShape.circle),
      child: Text(
        initial,
        style: TextStyle(fontSize: HrisType.sm, fontWeight: HrisType.semibold, height: 1, color: t.primaryContrast),
      ),
    );

    final path = imageUrl?.trim() ?? '';
    final base = baseUrl?.trim() ?? '';
    if (path.isEmpty || (base.isEmpty && !path.startsWith('http'))) return letter;

    return ClipOval(
      child: Image.network(
        path.startsWith('http') ? path : '$base$path',
        width: HrisSize.avatar,
        height: HrisSize.avatar,
        fit: BoxFit.cover,
        // The sandbox runs behind ngrok, which otherwise answers with its warning page.
        headers: const {'ngrok-skip-browser-warning': 'true'},
        errorBuilder: (_, _, _) => letter,
      ),
    );
  }
}
