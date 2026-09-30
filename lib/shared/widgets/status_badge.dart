import 'package:flutter/material.dart';

import '../tokens.dart';

/// The web Badge (Badge.module.css): a 20px rectangle, radius 2, with a soft
/// tone background, its border and text colour, 12px medium, and a 6px square
/// tone marker before the label. `neutral` for anything that carries no
/// verdict; `quiet` (muted text, no fill, no border) for days that are simply
/// not work days — the web's rest day / no record.
enum StatusTone { success, warning, info, danger, neutral, quiet }

class StatusBadge extends StatelessWidget {
  final String text;
  final StatusTone tone;

  const StatusBadge(this.text, {super.key, this.tone = StatusTone.neutral});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final quiet = tone == StatusTone.quiet;
    final (bg, border, fg) = switch (tone) {
      StatusTone.success => (t.success.bg, t.success.border, t.success.text),
      StatusTone.warning => (t.warning.bg, t.warning.border, t.warning.text),
      StatusTone.info => (t.info.bg, t.info.border, t.info.text),
      StatusTone.danger => (t.danger.bg, t.danger.border, t.danger.text),
      StatusTone.neutral => (t.neutral.bg, t.neutral.border, t.neutral.text),
      StatusTone.quiet => (Colors.transparent, Colors.transparent, t.muted),
    };
    return Container(
      constraints: const BoxConstraints(minHeight: 20),
      padding: EdgeInsets.symmetric(horizontal: quiet ? 0 : 6),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(HrisRadius.badge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: fg, borderRadius: BorderRadius.circular(1)),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              style: TextStyle(fontFamily: HrisFont.sans, fontSize: HrisType.xxs, fontWeight: HrisType.medium, height: 16 / 12, color: fg),
            ),
          ),
        ],
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
    'rest_day' || 'no_record' => StatusTone.quiet,
    _ => StatusTone.neutral,
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
