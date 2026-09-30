import 'package:flutter/material.dart';

import '../tokens.dart';

/// The web page header (PageHeader.jsx): the h1 — 20/28 semibold — with an
/// optional secondary line under it, on the page background above the content.
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final EdgeInsetsGeometry padding;

  const PageHeader(
    this.title, {
    super.key,
    this.subtitle,
    this.padding = const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s4, HrisSpace.s4, HrisSpace.s3),
  });

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: HrisType.heading, fontWeight: HrisType.semibold, height: 28 / 20, color: t.text)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text2)),
          ],
        ],
      ),
    );
  }
}

/// The web's small section label (the sidebar's MAIN / SYSTEM, a panel's
/// field group): 12px semibold, secondary colour, caps with the web's single
/// tracking value (.04em). Upper-cases its text itself, as it always has.
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
          height: 16 / 12,
          color: t.text2,
          letterSpacing: HrisType.xxs * 0.04,
        ),
      ),
    );
  }
}
