import 'package:flutter/material.dart';

import '../tokens.dart';

/// The web top-bar avatar (Topbar.module.css .avatar): a 32px primary circle
/// with the account's first initial in white.
class UserAvatar extends StatelessWidget {
  final String name;

  const UserAvatar(this.name, {super.key});

  String get initial {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return Container(
      width: HrisSize.avatar,
      height: HrisSize.avatar,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: t.primary, shape: BoxShape.circle),
      child: Text(
        initial,
        style: TextStyle(fontSize: HrisType.sm, fontWeight: HrisType.semibold, height: 1, color: t.primaryContrast),
      ),
    );
  }
}
