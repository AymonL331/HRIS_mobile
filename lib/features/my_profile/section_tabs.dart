import 'package:flutter/material.dart';

import '../../shared/tokens.dart';

/// One tab of [SectionTabs].
class SectionTab {
  final String key;
  final String label;

  const SectionTab(this.key, this.label);
}

/// The web SectionTabs (SectionTabs.module.css): underline tabs that WRAP onto
/// further rows instead of scrolling sideways, over one 1px baseline. Active =
/// text colour, semibold, 2px primary underline; the rest secondary text.
class SectionTabs extends StatelessWidget {
  final List<SectionTab> tabs;
  final String activeKey;
  final ValueChanged<String> onChange;
  final String? label;

  const SectionTabs({
    super.key,
    required this.tabs,
    required this.activeKey,
    required this.onChange,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return Semantics(
      container: true,
      label: label,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.border)),
        ),
        child: Wrap(
          runSpacing: 2,
          children: [
            for (final tab in tabs)
              _TabButton(
                tab: tab,
                active: tab.key == activeKey,
                onTap: () => onChange(tab.key),
              ),
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final SectionTab tab;
  final bool active;
  final VoidCallback onTap;

  const _TabButton({
    required this.tab,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return Semantics(
      button: true,
      selected: active,
      child: InkWell(
        key: Key('section_tab_${tab.key}'),
        onTap: onTap,
        // Sized to its label (a Container with an alignment would stretch to the
        // whole row and stack every tab on its own line).
        child: IntrinsicWidth(
          child: Container(
            height: HrisSize.touch,
            padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s3),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: active ? t.primary : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Text(
              tab.label,
              style: TextStyle(
                fontSize: HrisType.sm,
                height: 1,
                fontWeight: active ? HrisType.semibold : HrisType.medium,
                color: active ? t.text : t.text2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
