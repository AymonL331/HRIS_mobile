import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/time/manila_time.dart';
import '../../shared/button_styles.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/message_banner.dart';
import '../../shared/widgets/status_badge.dart';
import 'notification_display.dart';
import 'notifications_controller.dart';
import 'reminder_models.dart';

/// My clock-in / clock-out reminders — the website's notifications page,
/// narrowed to the reminder ladder. Pushed over the shell (not a sidebar
/// destination): it is reached from the bell, and the back gesture returns.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  /// Open it over the current page, carrying the controller across the route
  /// boundary (a pushed route sits above the shell's providers).
  static Future<void> open(BuildContext context, NotificationsController controller) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChangeNotifierProvider<NotificationsController>.value(
            value: controller,
            child: const NotificationsScreen(),
          ),
        ),
      );

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Opening the list re-reads it, the way opening the web panel does.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<NotificationsController>().load();
    });
  }

  Future<void> _acknowledge(NotificationsController c, AppNotification n) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await c.acknowledge(n.id);
      messenger.showSnackBar(const SnackBar(content: Text('Acknowledged.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not record that. Try again.')));
    }
  }

  Future<bool> _confirmRemove() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this reminder?'),
        content: const Text('It leaves your inbox here and on the website. Removing it does not count as a response.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: HrisButtonStyles.danger(ctx),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    return yes ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<NotificationsController>();
    final t = HrisTokens.of(context);
    final now = DateTime.now().toUtc();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (c.unreadCount > 0)
            TextButton(onPressed: c.markAllRead, child: const Text('Mark all read')),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: c.load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s3, HrisSpace.s4, HrisSpace.s5),
          children: [
            if (c.error != null && c.items.isEmpty) ...[
              MessageBanner.error(c.error!),
              const SizedBox(height: HrisSpace.s3),
            ],
            if (c.loading && c.items.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: HrisSpace.s6),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (c.items.isEmpty && c.error == null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s5, vertical: HrisSpace.s6),
                decoration: BoxDecoration(
                  color: t.surface,
                  border: Border.all(color: t.border),
                  borderRadius: BorderRadius.circular(HrisRadius.panel),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: t.neutral.bg, borderRadius: BorderRadius.circular(HrisRadius.control)),
                      child: Icon(Icons.notifications_none, size: 22, color: t.text2),
                    ),
                    const SizedBox(height: HrisSpace.s3),
                    Text('No reminders', style: TextStyle(fontSize: HrisType.md, fontWeight: HrisType.semibold, height: 24 / 16, color: t.text)),
                    const SizedBox(height: HrisSpace.s1),
                    Text(
                      'Clock-in and clock-out reminders set by HR will show here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text2),
                    ),
                  ],
                ),
              ),
            if (c.items.isNotEmpty)
              Container(
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
                      // Each row captures its own notification, as before.
                      for (final (i, n) in c.items.indexed) ...[
                        if (i > 0) Divider(height: 1, thickness: 1, color: t.border),
                        Dismissible(
                          key: ValueKey('notification-${n.id}'),
                          direction: DismissDirection.endToStart,
                          confirmDismiss: (_) => _confirmRemove(),
                          onDismissed: (_) => c.remove(n.id).catchError((_) {}),
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: HrisSpace.s5),
                            color: t.danger.bg,
                            child: Icon(Icons.delete_outline, color: t.danger.text),
                          ),
                          child: _NotificationCard(
                            notification: n,
                            now: now,
                            onTap: n.isRead ? null : () => c.markRead(n.id),
                            onAcknowledge: () => _acknowledge(c, n),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final AppNotification notification;
  final DateTime now;
  final VoidCallback? onTap;
  final VoidCallback onAcknowledge;

  const _NotificationCard({required this.notification, required this.now, required this.onTap, required this.onAcknowledge});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final n = notification;
    final tone = toneOf(n);
    final tag = toneTag(tone);
    final ack = ackStateOf(n, now);
    final when = relativeTime(n.createdAt, now, ManilaTime.dateTime);

    // The web's notification row: the title (bold while unread) with the
    // square unread marker, the tone tag under it, the message in the
    // secondary colour, then the time and the response.
    return Material(
      color: t.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(HrisSpace.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!n.isRead)
                    Padding(
                      padding: const EdgeInsets.only(top: 7, right: HrisSpace.s2),
                      child: Semantics(
                        label: 'Unread',
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(color: t.primaryText, borderRadius: BorderRadius.circular(1)),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      plainText(n.title),
                      style: TextStyle(
                        fontSize: HrisType.sm,
                        fontWeight: n.isRead ? HrisType.medium : HrisType.semibold,
                        height: 20 / 14,
                        color: t.text,
                      ),
                    ),
                  ),
                ],
              ),
              if (tag != null) ...[
                const SizedBox(height: HrisSpace.s1 + 2),
                StatusBadge(tag, tone: statusToneOf(tone)),
              ],
              const SizedBox(height: HrisSpace.s1 + 2),
              Text(plainText(n.message), style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text2)),
              const SizedBox(height: HrisSpace.s1),
              Text(when, style: TextStyle(fontSize: HrisType.xs, height: 16 / 12, color: t.text2)),
              if (ack != null) ...[
                const SizedBox(height: HrisSpace.s2),
                Align(
                  alignment: Alignment.centerRight,
                  child: _AckRow(state: ack, deadline: n.ackDeadlineAt, onAcknowledge: onAcknowledge),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AckRow extends StatelessWidget {
  final AckState state;
  final DateTime? deadline;
  final VoidCallback onAcknowledge;

  const _AckRow({required this.state, required this.deadline, required this.onAcknowledge});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    if (state.done) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, size: 16, color: state.late ? t.warning.text : t.success.text),
          const SizedBox(width: HrisSpace.s1),
          Text(
            state.late ? 'Acknowledged (late)' : 'Acknowledged',
            style: TextStyle(fontSize: HrisType.xs, fontWeight: HrisType.semibold, height: 16 / 12, color: state.late ? t.warning.text : t.success.text),
          ),
        ],
      );
    }
    final d = deadline;
    final hint = state.overdue
        ? 'Response window closed'
        : d == null
            ? null
            : 'Respond by ${ManilaTime.time(d)}';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hint != null) ...[
          Flexible(child: Text(hint, style: TextStyle(fontSize: HrisType.xs, height: 16 / 12, color: state.overdue ? t.danger.text : t.text2))),
          const SizedBox(width: HrisSpace.s3),
        ],
        OutlinedButton.icon(
          onPressed: onAcknowledge,
          style: OutlinedButton.styleFrom(
            foregroundColor: t.primaryText,
            side: BorderSide(color: t.primaryText),
            padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s3),
          ),
          icon: const Icon(Icons.check, size: 16),
          label: const Text("I've got this"),
        ),
      ],
    );
  }
}
