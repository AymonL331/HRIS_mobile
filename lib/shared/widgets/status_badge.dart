import 'package:flutter/material.dart';

import '../tokens.dart';

/// The web Badge (Badge.module.css): a pill with a soft tone background, its
/// border and text colour, 11.52px semibold. Five tones, `neutral` for
/// anything that carries no verdict.
enum StatusTone { success, warning, info, danger, neutral }

class StatusBadge extends StatelessWidget {
  final String text;
  final StatusTone tone;

  const StatusBadge(this.text, {super.key, this.tone = StatusTone.neutral});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final (bg, border, fg) = switch (tone) {
      StatusTone.success => (t.success.bg, t.success.border, t.success.text),
      StatusTone.warning => (t.warning.bg, t.warning.border, t.warning.text),
      StatusTone.info => (t.info.bg, t.info.border, t.info.text),
      StatusTone.danger => (t.danger.bg, t.danger.border, t.danger.text),
      StatusTone.neutral => (Color.alphaBlend(t.hover, t.surface), t.border, t.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s3, vertical: HrisSpace.s1),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(HrisRadius.pill),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: HrisType.xxs, fontWeight: HrisType.semibold, height: 1.4, color: fg),
      ),
    );
  }
}

/// The web DTR's tone for a projected day (constants/attendanceEnums.js):
/// a worked day is judged by its row status, any other day by its type.
StatusTone dtrDayTone(String dayType, String? status) {
  if (dayType == 'worked' || dayType == 'absent') return dtrStatusTone(status ?? dayType);
  return switch (dayType) {
    'on_leave' => StatusTone.success,
    'holiday' => StatusTone.info,
    _ => StatusTone.neutral, // rest_day, no_record
  };
}

/// ATT_STATUS_TONE: present success · late warning · absent danger · OB info.
StatusTone dtrStatusTone(String? status) => switch (status) {
      'present' => StatusTone.success,
      'late' => StatusTone.warning,
      'absent' => StatusTone.danger,
      'official_business' => StatusTone.info,
      _ => StatusTone.neutral,
    };

/// ATT_FLAG_TONE: undertime warning · half_day info · on_leave success.
StatusTone dtrFlagTone(String flag) => switch (flag) {
      'undertime' => StatusTone.warning,
      'half_day' => StatusTone.info,
      'on_leave' => StatusTone.success,
      _ => StatusTone.neutral,
    };

/// CAPTURE_METHOD_TONE: face / device / mobile info · system warning · else neutral.
StatusTone captureMethodTone(String? method) => switch (method) {
      'face' || 'device' || 'mobile' => StatusTone.info,
      'system' => StatusTone.warning,
      _ => StatusTone.neutral,
    };
