import 'package:flutter/material.dart';

import '../tokens.dart';

/// The web panel: surface, 1px border, radius 6, NO shadow (borders over
/// shadows). The danger tone is the tinted alert panel. Content is clipped to
/// the radius so a ruled list or an image inside meets the edge cleanly.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? maxWidth;
  final bool centered;
  final AppCardTone tone;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(HrisSpace.s4),
    this.maxWidth,
    this.centered = false,
    this.tone = AppCardTone.surface,
  });

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final danger = tone == AppCardTone.danger;
    Widget card = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: danger ? t.danger.bg : t.surface,
        border: Border.all(color: danger ? t.danger.border : t.border),
        borderRadius: BorderRadius.circular(HrisRadius.panel),
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(HrisRadius.panel - 1),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      ),
    );
    if (maxWidth != null) {
      card = ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth!), child: card);
    }
    return centered ? Center(child: card) : card;
  }
}

enum AppCardTone { surface, danger }
