import 'package:flutter/material.dart';

enum BannerTone { info, error, success, warning }

/// An inline message strip (never a toast): errors and reasons stay on screen
/// until the user acts, so a refusal is never missed.
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
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg, icon) = switch (tone) {
      BannerTone.error => (scheme.errorContainer, scheme.onErrorContainer, Icons.error_outline),
      BannerTone.success => (scheme.tertiaryContainer, scheme.onTertiaryContainer, Icons.check_circle_outline),
      BannerTone.warning => (scheme.secondaryContainer, scheme.onSecondaryContainer, Icons.warning_amber_outlined),
      BannerTone.info => (scheme.primaryContainer, scheme.onPrimaryContainer, Icons.info_outline),
    };
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: fg),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(color: fg, height: 1.35))),
            if (onClose != null)
              IconButton(
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close, size: 18, color: fg),
                onPressed: onClose,
              ),
          ],
        ),
      ),
    );
  }
}
