import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../shared/tokens.dart';
import 'notifications_controller.dart';

/// The top-bar bell with its unread badge — the website's NotificationBell,
/// minus the dropdown: on a phone the list is its own page.
class NotificationBell extends StatelessWidget {
  final VoidCallback onOpen;

  const NotificationBell({super.key, required this.onOpen});

  static String badgeText(int count) => count > 99 ? '99+' : '$count';

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final unread = context.select<NotificationsController, int>((c) => c.unreadCount);
    return IconButton(
      tooltip: 'Notifications',
      onPressed: onOpen,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(unread > 0 ? Icons.notifications : Icons.notifications_outlined),
          if (unread > 0)
            Positioned(
              right: -6,
              top: -4,
              child: Semantics(
                label: '$unread unread',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 16),
                  decoration: BoxDecoration(
                    color: t.danger.solid,
                    borderRadius: BorderRadius.circular(HrisRadius.pill),
                    border: Border.all(color: t.surface, width: 1.5),
                  ),
                  child: Text(
                    badgeText(unread),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10, fontWeight: HrisType.semibold, height: 1.2, color: t.primaryContrast),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
