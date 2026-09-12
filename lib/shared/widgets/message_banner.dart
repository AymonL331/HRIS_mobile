import 'package:flutter/material.dart';

import '../tokens.dart';

enum BannerTone { info, error, success, warning }

/// An inline message strip (never a toast): errors and reasons stay on screen
/// until the user acts, so a refusal is never missed. Styled like the web's
/// toast/alert (Toast.module.css): the tone's soft background and border with
/// a 4px accent down the left edge.
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
    final (set, accent, icon) = switch (tone) {
      BannerTone.error => (t.danger, t.danger.text, Icons.error_outline),
      BannerTone.success => (t.success, t.success.solid, Icons.check_circle_outline),
      BannerTone.warning => (t.warning, t.warning.text, Icons.warning_amber_outlined),
      BannerTone.info => (t.info, t.info.text, Icons.info_outline),
    };
    return Container(
      decoration: BoxDecoration(
        color: set.bg,
        border: Border.all(color: set.border),
        borderRadius: BorderRadius.circular(HrisRadius.sm),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(HrisRadius.sm - 1),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(HrisSpace.s3, HrisSpace.s3, HrisSpace.s2, HrisSpace.s3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, size: 20, color: accent),
                      const SizedBox(width: HrisSpace.s2 + 2),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(text, style: TextStyle(fontSize: HrisType.sm, color: t.text, height: 1.4)),
                        ),
                      ),
                      if (onClose != null)
                        IconButton(
                          tooltip: 'Dismiss',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          icon: Icon(Icons.close, size: 18, color: t.muted),
                          onPressed: onClose,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
