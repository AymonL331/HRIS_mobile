import 'package:flutter/material.dart';

import '../tokens.dart';

/// The web page header: a 22.4px semibold title with an optional muted
/// subtitle, sitting on the page background above the content.
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const PageHeader(this.title, {super.key, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s4, HrisSpace.s4, HrisSpace.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: HrisType.heading, fontWeight: HrisType.semibold, height: 1.25, color: t.text)),
          if (subtitle != null) ...[
            const SizedBox(height: HrisSpace.s1),
            Text(subtitle!, style: TextStyle(fontSize: HrisType.sm, height: 1.4, color: t.muted)),
          ],
        ],
      ),
    );
  }
}

/// The web's uppercase micro-label (sidebar section titles, tile labels):
/// 11.52px semibold, muted, letter-spaced. Upper-cases its text itself.
class SectionLabel extends StatelessWidget {
  final String text;
  final EdgeInsetsGeometry padding;

  const SectionLabel(
    this.text, {
    super.key,
    this.padding = const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s4, HrisSpace.s4, HrisSpace.s1),
  });

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return Padding(
      padding: padding,
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: HrisType.xxs,
          fontWeight: HrisType.semibold,
          height: 1.2,
          color: t.muted,
          letterSpacing: HrisType.xxs * 0.08,
        ),
      ),
    );
  }
}
