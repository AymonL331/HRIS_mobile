import 'package:flutter/material.dart';

import '../tokens.dart';

enum BannerTone { info, error, success, warning }

/// The web's inline alert / note: a tinted box with a 1px tone border and
/// radius 4 (no coloured edge stripe), the tone's icon, then the message in
/// body text. [onClose] adds a Dismiss button.
class MessageBanner extends StatelessWidget {
  final String text;
  final BannerTone tone;
  final VoidCallback? onClose;

  const MessageBanner(this.text, {super.key, this.tone = BannerTone.info, this.onClose});
  const MessageBanner.info(this.text, {super.key, this.onClose}) : tone = BannerTone.info;
  const MessageBanner.error(this.text, {super.key, this.onClose}) : tone = BannerTone.error;
  const MessageBanner.success(this.text, {super.key, this.onClose}) : tone = BannerTone.success;
  const MessageBanner.warning(this.text, {super.key, this.onClose}) : tone = BannerTone.warning;

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final (set, icon) = switch (tone) {
      BannerTone.error => (t.danger, Icons.error_outline),
      BannerTone.success => (t.success, Icons.check_circle_outline),
      BannerTone.warning => (t.warning, Icons.warning_amber_outlined),
      BannerTone.info => (t.info, Icons.info_outline),
    };
    return Container(
      decoration: BoxDecoration(
        color: set.bg,
        border: Border.all(color: set.border),
        borderRadius: BorderRadius.circular(HrisRadius.control),
      ),
      padding: EdgeInsets.fromLTRB(HrisSpace.s3, HrisSpace.s3 - 2, onClose != null ? HrisSpace.s1 : HrisSpace.s3, HrisSpace.s3 - 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 18, color: set.solid),
          ),
          const SizedBox(width: HrisSpace.s2),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(text, style: TextStyle(fontFamily: HrisFont.sans, fontSize: HrisType.sm, color: t.text, height: 20 / 14)),
            ),
          ),
          if (onClose != null)
            IconButton(
              tooltip: 'Dismiss',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: HrisSize.touch, minHeight: HrisSize.touch),
              style: IconButton.styleFrom(minimumSize: const Size(HrisSize.touch, HrisSize.touch)),
              icon: Icon(Icons.close, size: 18, color: t.muted),
              onPressed: onClose,
            ),
        ],
      ),
    );
  }
}
