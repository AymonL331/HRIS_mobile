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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HrisRadius.control)),
        textStyle: TextStyle(fontFamily: HrisFont.sans, fontSize: fontSize, fontWeight: HrisType.medium, height: 1.25),
        padding: padding,
        minimumSize: Size(64, minHeight),
        tapTargetSize: MaterialTapTargetSize.padded,
      );

  static const _pad = EdgeInsets.symmetric(horizontal: HrisSpace.s4, vertical: HrisSpace.s3);
  static const _padLg = EdgeInsets.symmetric(horizontal: HrisSpace.s5, vertical: HrisSpace.s3);

  static ButtonStyle _secondaryColours(HrisTokens t, ButtonStyle base) => base.copyWith(
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? t.surfaceSunken : t.surface),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? t.muted : t.text),
        iconColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? t.muted : t.text),
        side: WidgetStateProperty.resolveWith(
          (s) => BorderSide(color: s.contains(WidgetState.disabled) ? t.border : t.borderStrong),
        ),
        overlayColor: WidgetStatePropertyAll(t.hover),
      );

  /// Button.module.css .secondary
  static ButtonStyle secondary(BuildContext context, {double minHeight = HrisSize.control}) =>
      _secondaryColours(HrisTokens.of(context), _base(context, minHeight: minHeight, fontSize: HrisType.sm, padding: _pad));

  /// .secondary at the large size (the web kiosk's Time Out; --control-h-lg on phones).
  static ButtonStyle secondaryLg(BuildContext context) =>
      _secondaryColours(HrisTokens.of(context), _base(context, minHeight: 48, fontSize: HrisType.md, padding: _padLg));

  /// .primary at the large size (the web kiosk's Time In).
  static ButtonStyle primaryLg(BuildContext context) =>
      _base(context, minHeight: 48, fontSize: HrisType.md, padding: _padLg);

  /// .danger — the destructive confirm (--danger-solid fill, white text).
  static ButtonStyle danger(BuildContext context) {
    final t = HrisTokens.of(context);
    return _base(context, minHeight: HrisSize.control, fontSize: HrisType.sm, padding: _pad).copyWith(
      backgroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled) ? t.surfaceSunken : t.danger.solid,
      ),
      foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? t.muted : t.primaryContrast),
      iconColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? t.muted : t.primaryContrast),
      overlayColor: WidgetStatePropertyAll(Colors.white.withValues(alpha: 0.08)),
    );
  }
}
