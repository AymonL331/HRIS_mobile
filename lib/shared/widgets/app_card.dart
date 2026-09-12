import 'package:flutter/material.dart';

import '../tokens.dart';

/// The web `.card`: surface, 1px border, radius 14, the soft card shadow,
/// 24px padding. [tone] danger gives the web ErrorState (danger background,
/// no shadow). [maxWidth] caps it the way the auth and time-clock cards are
/// capped on the website; [centered] centres its children.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? maxWidth;
  final bool centered;
  final AppCardTone tone;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(HrisSpace.s5),
    this.maxWidth,
    this.centered = false,
    this.tone = AppCardTone.surface,
  });

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final danger = tone == AppCardTone.danger;
    // A transparent Material inside the decoration so tiles and buttons in the
    // card paint their ink on it (Flutter asserts when a ListTile sits under
    // a coloured DecoratedBox with no Material between).
    Widget card = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: danger ? t.danger.bg : t.surface,
        border: Border.all(color: danger ? t.danger.border : t.border),
        borderRadius: BorderRadius.circular(HrisRadius.md),
        boxShadow: danger ? null : [t.shadowCard],
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(HrisRadius.md - 1),
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
