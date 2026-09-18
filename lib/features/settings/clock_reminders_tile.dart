import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/device/device_readiness_service.dart';
import '../../core/device/oem_hints.dart';
import '../../core/time/manila_time.dart';
import '../../shared/tokens.dart';
import '../reminders/reminder_coordinator.dart';
import '../reminders/reminder_models.dart';

/// Settings › Phone: will this phone deliver the clock-in / clock-out reminders?
///
/// Three things decide it and none of them is visible from the Time Clock:
/// notifications allowed, exact alarms allowed (Android 12 asks; 13+ grants
/// it to the app outright), and whether any reminder is armed at all — which
/// says whether HR configured a ladder for this branch and when the next one
/// is. Opening the row re-plans quietly; there is deliberately NO button to
/// "sync" — keeping the phone current is the app's job, never the employee's
/// (user decision 2026-09-17).
class ClockRemindersTile extends StatefulWidget {
  const ClockRemindersTile({super.key});

  @override
  State<ClockRemindersTile> createState() => _ClockRemindersTileState();
}

class _ClockRemindersTileState extends State<ClockRemindersTile> with WidgetsBindingObserver {
  ReminderCoordinator? _reminders;
  DeviceReadinessService? _device;
  DeviceReadiness? _readiness;
  ReminderAlarm? _next;

  T? _optional<T>() {
    try {
      return context.read<T>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reminders = _optional<ReminderCoordinator?>();
    _device = _optional<DeviceReadinessService>();
    _refresh();
  }

  /// Re-plan quietly, then read the state — so the row is current the moment
  /// it is looked at, without a button.
  Future<void> _refresh() async {
    await _reminders?.resync();
    await _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Re-checked on every return to the foreground — the employee usually comes
  /// back FROM the settings page they were just sent to.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final r = _reminders;
    if (r == null) return;
    DeviceReadiness? readiness;
    try {
      readiness = await _device?.check();
    } catch (_) {
      // Unknown stays unknown: a warning that might be wrong is worse than none.
    }
    final next = await r.next();
    if (!mounted) return;
    setState(() {
      _readiness = readiness;
      _next = next;
    });
  }

  Future<void> _fix(Future<void> Function()? request) async {
    if (request == null) return;
    try {
      await request();
    } catch (_) {}
    await _check();
  }

  @override
  Widget build(BuildContext context) {
    if (_reminders == null) return const SizedBox.shrink();
    final t = HrisTokens.of(context);
    final noNotifications = _readiness?.notificationsGranted == false;
    final noExactAlarms = _readiness?.exactAlarmsGranted == false;
    final blocked = noNotifications || noExactAlarms;
    final next = _next;
    final Color colour = blocked ? t.warning.text : (next == null ? t.muted : t.success.text);
    final String status = blocked ? 'Needs attention' : (next == null ? 'None scheduled' : 'Ready');
    final String detail = noNotifications
        ? 'Notifications are off — reminders cannot be shown.'
        : noExactAlarms
            ? 'Exact alarms are off — reminders may arrive late or not at all.'
            : next == null
                ? 'No reminder is scheduled. HR sets the reminder times on the website.'
                : 'Next: ${next.isClockIn ? 'clock-in' : 'clock-out'} reminder · ${ManilaTime.dateTime(next.firesAt)}.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: Icon(
            blocked ? Icons.notifications_off_outlined : Icons.notifications_active_outlined,
            color: colour,
          ),
          title: const Text('Clock reminders'),
          subtitle: Text(detail),
          trailing: Text(status, style: TextStyle(fontSize: HrisType.xs, fontWeight: HrisType.semibold, color: colour)),
        ),
        if (noNotifications)
          Padding(
            padding: const EdgeInsets.fromLTRB(HrisSpace.s4, 0, HrisSpace.s4, HrisSpace.s3),
            child: OutlinedButton.icon(
              onPressed: () => _fix(_device?.requestNotifications),
              icon: const Icon(Icons.notifications_outlined),
              label: const Text('Allow notifications'),
            ),
          ),
        // Steps, not a button: no dialog can set this switch (2026-09-18 — the
        // button that tried did nothing). Re-checked on return to the app.
        if (noExactAlarms)
          Padding(
            padding: const EdgeInsets.fromLTRB(HrisSpace.s4, 0, HrisSpace.s4, HrisSpace.s3),
            child: _ExactAlarmSteps(hint: oemExactAlarmHint(_readiness?.manufacturer ?? ''), color: t.muted),
          ),
      ],
    );
  }
}

class _ExactAlarmSteps extends StatelessWidget {
  final OemHint hint;
  final Color color;

  const _ExactAlarmSteps({required this.hint, required this.color});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 12, height: 1.45);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'To allow exact alarms on ${hint.brand == 'this' ? 'this' : 'your ${hint.brand}'} phone:',
          style: style.copyWith(fontWeight: FontWeight.w600, color: color),
        ),
        for (var i = 0; i < hint.steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('${i + 1}. ${hint.steps[i]}', style: style.copyWith(color: color)),
          ),
        Padding(
          padding: const EdgeInsets.only(top: HrisSpace.s1),
          child: Text('Then come back to HRIS — this row updates by itself.', style: style.copyWith(color: color)),
        ),
      ],
    );
  }
}
