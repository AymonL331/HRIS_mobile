import 'package:flutter/material.dart';

import '../tokens.dart';

// Presentational building blocks that match the web kit (components/ui):
// Panel, the ruled list, Empty/Error/Loading states and the small note. They
// hold no state and no text of their own — every word comes from the caller.

/// Panel.jsx — surface, 1px border, radius 6, no shadow; an optional header
/// row (title + trailing widget) ruled off from the body.
class SectionPanel extends StatelessWidget {
  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const SectionPanel({
    super.key,
    this.title,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(HrisSpace.s4),
  });

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(HrisRadius.panel),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(HrisRadius.panel - 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null || trailing != null)
              Container(
                padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s3, HrisSpace.s3, HrisSpace.s3),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.border))),
                child: Row(
                  children: [
                    if (title != null)
                      Expanded(
                        child: Text(
                          title!,
                          style: TextStyle(fontSize: HrisType.md, fontWeight: HrisType.semibold, height: 24 / 16, color: t.text),
                        ),
                      ),
                    ?trailing,
                  ],
                ),
              ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

/// The web's ruled list: one bordered panel whose rows are separated by 1px
/// rules — instead of a stack of separate cards.
class RuledList extends StatelessWidget {
  final List<Widget> children;

  const RuledList({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(HrisRadius.panel),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(HrisRadius.panel - 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: t.border),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// One row of a [RuledList]: 48dp minimum, 12/16 padding, an optional tap.
class RuledRow extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final bool selected;

  const RuledRow({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: HrisSpace.s4, vertical: HrisSpace.s3),
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: HrisSize.touch),
      child: Padding(padding: padding, child: child),
    );
    return Material(
      color: selected ? t.primarySoft : Colors.transparent,
      child: onTap == null ? row : InkWell(onTap: onTap, child: row),
    );
  }
}

/// EmptyState / ErrorState (States.module.css): centred, a 14 semibold title,
/// a secondary line, an optional action. Error adds the square danger marker.
class StatePanel extends StatelessWidget {
  final String title;
  final String? message;
  final Widget? action;
  final bool error;
  final bool framed;

  const StatePanel({
    super.key,
    required this.title,
    this.message,
    this.action,
    this.error = false,
    this.framed = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s6, vertical: HrisSpace.s8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: t.danger.solid, borderRadius: BorderRadius.circular(1)),
                ),
                const SizedBox(width: HrisSpace.s2),
              ],
              Flexible(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: HrisType.sm, fontWeight: HrisType.semibold, height: 20 / 14, color: t.text),
                ),
              ),
            ],
          ),
          if (message != null) ...[
            const SizedBox(height: HrisSpace.s1),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text2),
            ),
          ],
          if (action != null) ...[const SizedBox(height: HrisSpace.s3), action!],
        ],
      ),
    );
    if (!framed) return Center(child: body);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(HrisRadius.panel),
      ),
      child: body,
    );
  }
}

/// LoadingBlock: a centred petrol spinner with room around it.
class LoadingBlock extends StatelessWidget {
  final String? semanticsLabel;

  const LoadingBlock({super.key, this.semanticsLabel});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: HrisSpace.s8),
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5, semanticsLabel: semanticsLabel),
          ),
        ),
      );
}

/// The web's small note: a square tone marker, then secondary text — no box.
/// For hints that sit under a control or a section (e.g. "Paid only for …").
class Note extends StatelessWidget {
  final String text;
  final StatusSet Function(HrisTokens t)? tone;

  const Note(this.text, {super.key, this.tone});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final marker = (tone ?? (t) => t.info)(t).solid;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: marker, borderRadius: BorderRadius.circular(1)),
          ),
        ),
        const SizedBox(width: HrisSpace.s2),
        Expanded(child: Text(text, style: TextStyle(fontSize: HrisType.xs, height: 18 / 12, color: t.text2))),
      ],
    );
  }
}
