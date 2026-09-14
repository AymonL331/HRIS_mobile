import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/session_controller.dart';
import '../../shared/button_styles.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/brand_mark.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/user_avatar.dart';

/// One destination in the sidebar. [index] is its page in the shell's stack, so
/// a section can be reordered or a destination moved between sections without
/// disturbing which page it opens.
class NavDestination {
  final int index;
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const NavDestination({required this.index, required this.label, required this.icon, required this.selectedIcon});
}

/// A titled group of destinations — the web sidebar's `.section` with its
/// uppercase `.sectionTitle`.
class NavSection {
  final String title;
  final List<NavDestination> items;

  const NavSection(this.title, this.items);
}

/// The app's navigation, as the WEBSITE draws it: the brand block over a
/// hairline, the signed-in account, then the destinations grouped under
/// uppercase section labels. Replaces the three bottom tabs — the app has
/// outgrown a tab bar, and this is the shape the same product already has in
/// the browser (Sidebar.module.css).
///
/// The active item wears `--color-primary-soft` with primary text, exactly as
/// `.itemActive` does on the web.
///
/// SIGN OUT is pinned to the drawer's FOOTER (user, 2026-09-14 — it used to sit
/// at the bottom of Settings, two taps and a scroll away). The footer, not the
/// list, because it is an ACTION that ends the session, not a place to go: kept
/// apart from the destinations by a hairline so it cannot be mistaken for one or
/// hit while reaching for Settings, and fixed in place so it never moves as
/// destinations are added. It still asks before signing out.
class AppDrawer extends StatelessWidget {
  final List<NavSection> sections;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final String username;
  final String? roleName;

  /// Called after the drawer closes when Sign out is tapped. No footer when null.
  final VoidCallback? onSignOut;

  const AppDrawer({
    super.key,
    required this.sections,
    required this.selectedIndex,
    required this.onSelect,
    required this.username,
    this.roleName,
    this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return Drawer(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: Border(right: BorderSide(color: t.border)),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // .brand — the top-bar height, the brand row, one hairline under it.
            Container(
              height: HrisSize.topBar,
              padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s5),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: t.border)),
              ),
              alignment: Alignment.centerLeft,
              child: const BrandMark(),
            ),
            // Who is signed in. On the web this is the top-bar account block;
            // on a phone the top bar has room for the avatar alone, so the name
            // and role live here where there is space to read them.
            Padding(
              padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s4, HrisSpace.s4, 0),
              child: Row(
                children: [
                  UserAvatar(username),
                  const SizedBox(width: HrisSpace.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: HrisType.sm,
                            fontWeight: HrisType.semibold,
                            height: 1.35,
                            color: t.text,
                          ),
                        ),
                        if (roleName != null && roleName!.isNotEmpty)
                          Text(
                            roleName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: HrisType.xxs, height: 1.4, color: t.muted),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(HrisSpace.s3, HrisSpace.s3, HrisSpace.s3, HrisSpace.s5),
                children: [
                  for (final section in sections) ...[
                    SectionLabel(
                      section.title,
                      padding: const EdgeInsets.fromLTRB(HrisSpace.s3, HrisSpace.s3, HrisSpace.s3, HrisSpace.s1),
                    ),
                    for (final item in section.items)
                      _NavItem(
                        item: item,
                        selected: item.index == selectedIndex,
                        onTap: () {
                          Navigator.of(context).pop();
                          onSelect(item.index);
                        },
                      ),
                  ],
                ],
              ),
            ),
            if (onSignOut != null)
              Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: t.border)),
                ),
                padding: const EdgeInsets.all(HrisSpace.s3),
                child: _SignOutItem(
                  onTap: () {
                    Navigator.of(context).pop();
                    onSignOut!();
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Ask, then sign out. Shared by every place that offers Sign out, so the
/// wording and the danger styling are defined once.
Future<void> confirmSignOut(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Sign out?'),
      content: const Text("You'll need your company code, username and password to sign back in."),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: HrisButtonStyles.danger(ctx),
          child: const Text('Sign out'),
        ),
      ],
    ),
  );
  if (ok == true && context.mounted) await context.read<SessionController>().logout();
}

/// The footer's Sign out: shaped like a destination row, in the danger tone so
/// it reads as leaving rather than going somewhere.
class _SignOutItem extends StatelessWidget {
  final VoidCallback onTap;

  const _SignOutItem({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(HrisRadius.sm),
        child: Padding(
          padding: const EdgeInsets.all(HrisSpace.s3),
          child: Row(
            children: [
              Icon(Icons.logout, size: 20, color: t.danger.text),
              const SizedBox(width: HrisSpace.s3),
              Expanded(
                child: Text(
                  'Sign out',
                  style: TextStyle(
                    fontSize: HrisType.sm,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                    color: t.danger.text,
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

/// Sidebar.module.css `.item` / `.itemActive`.
class _NavItem extends StatelessWidget {
  final NavDestination item;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({required this.item, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final fg = selected ? t.primary : t.text;
    return Semantics(
      selected: selected,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(HrisRadius.sm),
          child: Ink(
            decoration: BoxDecoration(
              color: selected ? t.primarySoft : Colors.transparent,
              borderRadius: BorderRadius.circular(HrisRadius.sm),
            ),
            child: Padding(
              padding: const EdgeInsets.all(HrisSpace.s3),
              child: Row(
                children: [
                  Icon(selected ? item.selectedIcon : item.icon, size: 20, color: selected ? t.primary : t.muted),
                  const SizedBox(width: HrisSpace.s3),
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(
                        fontSize: HrisType.sm,
                        fontWeight: selected ? HrisType.semibold : FontWeight.w500,
                        height: 1.35,
                        color: fg,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
