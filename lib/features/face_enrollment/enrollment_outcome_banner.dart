import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/tokens.dart';
import '../../shared/widgets/app_card.dart';
import 'face_enrollment_models.dart';

/// Remembers, on this phone, which enrollment outcomes the employee dismissed.
///
/// One notice per EMPLOYEE, OUTCOME and SUBMISSION: a second rejected submission
/// shows again even after the first was dismissed, and another employee signing
/// in on the same phone still sees their own.
class EnrollmentNoticeStore {
  static const _prefsKey = 'face_enrollment.dismissed_outcomes';
  static const _keep = 20;

  const EnrollmentNoticeStore();

  /// Null when there is nothing to tell (only a rejected or blocked new face is).
  static String? noticeKey(String employeeCode, SelfEnrollmentState state) {
    if (state.phase != SelfEnrollmentPhase.rejected && state.phase != SelfEnrollmentPhase.blocked) return null;
    return '$employeeCode|${state.phase.name}|${state.submittedAt?.toUtc().toIso8601String() ?? ''}';
  }

  Future<bool> isDismissed(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_prefsKey) ?? const <String>[]).contains(key);
  }

  Future<void> dismiss(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final list = [...(prefs.getStringList(_prefsKey) ?? const <String>[])]
      ..remove(key)
      ..add(key);
    await prefs.setStringList(_prefsKey, list.length > _keep ? list.sublist(list.length - _keep) : list);
  }
}

/// On the clock, for an employee who IS enrolled: HR rejected their NEW face, or
/// the server blocked it (it matches another employee).
///
/// Until 2026-09-15 the re-enroll banner simply vanished at that point — the
/// server sent the outcome and HR's reason, and the screen showed neither, so the
/// employee was never told why. Their current face keeps working either way, and
/// the banner says so. It hides itself when dismissed (remembered per submission).
class EnrollmentOutcomeBanner extends StatefulWidget {
  final SelfEnrollmentState state;
  final String employeeCode;
  final EnrollmentNoticeStore store;

  const EnrollmentOutcomeBanner({
    super.key,
    required this.state,
    required this.employeeCode,
    this.store = const EnrollmentNoticeStore(),
  });

  @override
  State<EnrollmentOutcomeBanner> createState() => _EnrollmentOutcomeBannerState();
}

class _EnrollmentOutcomeBannerState extends State<EnrollmentOutcomeBanner> {
  String? _key;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void didUpdateWidget(covariant EnrollmentOutcomeBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (EnrollmentNoticeStore.noticeKey(widget.employeeCode, widget.state) != _key) _check();
  }

  // Hidden until the phone has confirmed this outcome was not dismissed, so a
  // dismissed banner never flashes back on a refresh.
  Future<void> _check() async {
    final key = EnrollmentNoticeStore.noticeKey(widget.employeeCode, widget.state);
    _key = key;
    _visible = false;
    if (key == null) return;
    final dismissed = await widget.store.isDismissed(key);
    if (!mounted || _key != key) return;
    setState(() => _visible = !dismissed);
  }

  Future<void> _dismiss() async {
    final key = _key;
    setState(() => _visible = false);
    if (key != null) await widget.store.dismiss(key);
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final t = HrisTokens.of(context);
    final blocked = widget.state.phase == SelfEnrollmentPhase.blocked;
    final reason = widget.state.reason?.trim();
    final hasReason = reason != null && reason.isNotEmpty;

    final title = blocked ? 'New face enrollment not accepted' : 'New face enrollment not approved';
    final body = blocked
        ? '${hasReason ? reason : "This face couldn't be accepted for your account."} '
            'You keep clocking with your current face.'
        : '${hasReason ? 'Reason: $reason\n\n' : ''}'
            'You keep clocking with your current face. If the app has trouble recognising you, '
            'ask HR to allow face enrollment again.';

    return Padding(
      padding: const EdgeInsets.only(bottom: HrisSpace.s3),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.face_retouching_off_outlined, size: 20, color: t.muted),
                const SizedBox(width: HrisSpace.s2),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: HrisType.md, fontWeight: HrisType.semibold, color: t.text),
                  ),
                ),
              ],
            ),
            const SizedBox(height: HrisSpace.s1),
            Text(body, style: TextStyle(fontSize: HrisType.sm, height: 1.45, color: t.muted)),
            const SizedBox(height: HrisSpace.s2),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: _dismiss, child: const Text('Dismiss')),
            ),
          ],
        ),
      ),
    );
  }
}
