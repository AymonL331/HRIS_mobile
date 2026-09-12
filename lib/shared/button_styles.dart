import 'package:flutter/material.dart';

import 'tokens.dart';

/// Call-site styles for the web button variants a theme cannot express on
/// its own. `FilledButton` and `FilledButton.tonal` share one theme, so a
/// tonal button that must LOOK secondary (the web's surface + border + text
/// colour) while REMAINING a FilledButton — the Time Out button, which the
/// tests find by type — takes [secondary] or [secondaryLg] here.
abstract final class HrisButtonStyles {
  static ButtonStyle _base(BuildContext context, {required double minHeight, required double fontSize, required EdgeInsets padding}) =>
      FilledButton.styleFrom(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HrisRadius.sm)),
        textStyle: TextStyle(fontSize: fontSize, fontWeight: HrisType.semibold, height: 1.2),
        padding: padding,
        minimumSize: Size(64, minHeight),
      );

  /// Button.module.css .secondary
  static ButtonStyle secondary(BuildContext context, {double minHeight = 48}) {
    final t = HrisTokens.of(context);
    return _base(context, minHeight: minHeight, fontSize: HrisType.md, padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s4, vertical: HrisSpace.s3)).copyWith(
      backgroundColor: WidgetStatePropertyAll(t.surface),
      foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? t.text.withValues(alpha: 0.6) : t.text),
      iconColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? t.text.withValues(alpha: 0.6) : t.text),
      side: WidgetStatePropertyAll(BorderSide(color: t.border)),
      overlayColor: WidgetStatePropertyAll(t.hover),
    );
  }

  /// .secondary at the .lg size (the web time clock's Time Out).
  static ButtonStyle secondaryLg(BuildContext context) {
    final t = HrisTokens.of(context);
    return _base(context, minHeight: 54, fontSize: HrisType.lg, padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s5, vertical: HrisSpace.s4)).copyWith(
      backgroundColor: WidgetStatePropertyAll(t.surface),
      foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? t.text.withValues(alpha: 0.6) : t.text),
      iconColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? t.text.withValues(alpha: 0.6) : t.text),
      side: WidgetStatePropertyAll(BorderSide(color: t.border)),
      overlayColor: WidgetStatePropertyAll(t.hover),
    );
  }

  /// .primary at the .lg size (the web time clock's Time In).
  static ButtonStyle primaryLg(BuildContext context) =>
      _base(context, minHeight: 54, fontSize: HrisType.lg, padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s5, vertical: HrisSpace.s4));

  /// .danger — the destructive confirm.
  static ButtonStyle danger(BuildContext context) {
    final t = HrisTokens.of(context);
    return _base(context, minHeight: 48, fontSize: HrisType.md, padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s4, vertical: HrisSpace.s3)).copyWith(
      backgroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled) ? t.danger.solid.withValues(alpha: 0.6) : t.danger.solid,
      ),
      foregroundColor: WidgetStatePropertyAll(t.primaryContrast),
      iconColor: WidgetStatePropertyAll(t.primaryContrast),
      overlayColor: WidgetStatePropertyAll(Colors.white.withValues(alpha: 0.08)),
    );
  }
}
