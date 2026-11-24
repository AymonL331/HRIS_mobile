import 'package:flutter/material.dart';

import '../../shared/tokens.dart';

/// The web ViewablePhotoAvatar: the employee's photo (or initials) in a circle;
/// with a photo, a tap opens it larger in a dialog titled with the name and
/// "Profile photo". Without one it is the plain initials avatar.
class ViewablePhotoAvatar extends StatelessWidget {
  final String firstName;
  final String lastName;
  final String? imageUrl;
  final String baseUrl;
  final String? title;
  final double size;

  const ViewablePhotoAvatar({
    super.key,
    required this.firstName,
    required this.lastName,
    required this.imageUrl,
    required this.baseUrl,
    this.title,
    this.size = 36,
  });

  /// First letter of up to two words — the web's formatInitials.
  String get initials {
    final words = '$firstName $lastName'.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2);
    final s = words.map((w) => w.characters.first).join().toUpperCase();
    return s.isEmpty ? '?' : s;
  }

  String? get _url {
    final p = imageUrl?.trim() ?? '';
    if (p.isEmpty) return null;
    return p.startsWith('http') ? p : '$baseUrl$p';
  }

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final letters = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: t.neutral.bg, shape: BoxShape.circle, border: Border.all(color: t.border)),
      child: Text(initials, style: TextStyle(fontSize: HrisType.xs, fontWeight: HrisType.semibold, height: 1, color: t.text2)),
    );
    final url = _url;
    if (url == null) return letters;
    final name = [firstName, lastName].where((s) => s.isNotEmpty).join(' ');
    return Semantics(
      button: true,
      label: 'View profile photo larger',
      child: GestureDetector(
        key: const Key('profile_avatar_view'),
        onTap: () => showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title?.isNotEmpty == true ? title! : (name.isEmpty ? 'Profile photo' : name)),
                Text('Profile photo', style: TextStyle(fontSize: HrisType.sm, fontWeight: FontWeight.normal, color: t.text2)),
              ],
            ),
            content: Image.network(
              url,
              fit: BoxFit.contain,
              headers: const {'ngrok-skip-browser-warning': 'true'},
              errorBuilder: (_, _, _) => const Text('Could not load the photo.'),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
          ),
        ),
        child: ClipOval(
          child: Image.network(
            url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            headers: const {'ngrok-skip-browser-warning': 'true'},
            errorBuilder: (_, _, _) => letters,
          ),
        ),
      ),
    );
  }
}
