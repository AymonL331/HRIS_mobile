import 'package:flutter/material.dart';

import 'tokens.dart';

/// The app's Material 3 theme built from the web HRIS tokens — one for each
/// brightness, so the phone follows the system dark mode exactly as the
/// website follows `prefers-color-scheme`. Every component theme below maps a
/// web CSS module (Button, Input, Badge, ConfirmDialog, Sidebar/Topbar …) onto
/// its Material counterpart; screens then need little or no per-widget styling.
ThemeData buildTheme([Brightness brightness = Brightness.light]) {
  final t = brightness == Brightness.dark ? HrisTokens.dark : HrisTokens.light;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: t.primary,
    onPrimary: t.primaryContrast,
    primaryContainer: t.primarySoft,
    onPrimaryContainer: t.primary,
    secondary: t.muted,
    onSecondary: t.surface,
    // Tonal buttons, selected segments and the nav indicator default to the
    // secondary container: making it primary-soft + primary gives them the
    // web's active look with no per-widget work.
    secondaryContainer: t.primarySoft,
    onSecondaryContainer: t.primary,
    tertiary: t.success.solid,
    onTertiary: t.primaryContrast,
    tertiaryContainer: t.success.bg,
    onTertiaryContainer: t.success.text,
    error: t.danger.solid,
    onError: t.primaryContrast,
    errorContainer: t.danger.bg,
    onErrorContainer: t.danger.text,
    surface: t.surface,
    onSurface: t.text,
    onSurfaceVariant: t.muted,
    surfaceContainerLowest: t.surface,
    surfaceContainerLow: t.surface,
    surfaceContainer: t.bg,
    surfaceContainerHigh: t.surface,
    surfaceContainerHighest: t.bg,
    outline: t.border,
    outlineVariant: t.border,
    inverseSurface: t.text,
    onInverseSurface: t.surface,
    inversePrimary: t.primarySoft,
    shadow: Colors.black,
    scrim: t.overlay,
    // No M3 tint overlays anywhere: the web's surfaces are flat.
    surfaceTint: Colors.transparent,
  );

  TextStyle ts(double size, {FontWeight weight = FontWeight.w400, double height = 1.45, Color? color, double? spacing}) =>
      TextStyle(fontSize: size, fontWeight: weight, height: height, color: color ?? t.text, letterSpacing: spacing ?? 0);

  final textTheme = TextTheme(
    displaySmall: ts(HrisType.stat, weight: HrisType.semibold, height: 1.15),
    headlineMedium: ts(HrisType.xl, weight: HrisType.semibold, height: 1.2),
    headlineSmall: ts(HrisType.heading, weight: HrisType.semibold, height: 1.25),
    titleLarge: ts(HrisType.lg, weight: HrisType.semibold, height: 1.3),
    titleMedium: ts(HrisType.md, weight: HrisType.semibold, height: 1.35),
    titleSmall: ts(HrisType.sm, weight: HrisType.semibold, height: 1.35),
    bodyLarge: ts(HrisType.md),
    bodyMedium: ts(HrisType.sm),
    bodySmall: ts(HrisType.xs, height: 1.4, color: t.muted),
    labelLarge: ts(HrisType.sm, weight: HrisType.semibold, height: 1.2),
    labelMedium: ts(HrisType.xs, weight: HrisType.semibold, height: 1.2, color: t.muted),
    labelSmall: ts(HrisType.xxs, weight: HrisType.semibold, height: 1.2, color: t.muted, spacing: HrisType.xxs * 0.08),
  );

  final radiusSm = BorderRadius.circular(HrisRadius.sm);
  final radiusMd = BorderRadius.circular(HrisRadius.md);
  final buttonText = ts(HrisType.md, weight: HrisType.semibold, height: 1.2);

  Color primaryBg(Set<WidgetState> s) {
    if (s.contains(WidgetState.disabled)) return t.primary.withValues(alpha: 0.6);
    if (s.contains(WidgetState.pressed)) return t.primaryHover;
    return t.primary;
  }

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    extensions: [t],
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.surface,
    dividerColor: t.border,
    hoverColor: t.hover,
    highlightColor: t.hover,
    splashColor: t.primarySoft,
    textTheme: textTheme,
    iconTheme: IconThemeData(color: t.muted),
    // The web top bar: surface, 60px, one hairline underneath, no shadow.
    appBarTheme: AppBarTheme(
      backgroundColor: t.surface,
      foregroundColor: t.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: HrisSize.topBar,
      shape: Border(bottom: BorderSide(color: t.border)),
      titleSpacing: HrisSpace.s5,
      centerTitle: false,
      titleTextStyle: ts(HrisType.lg, weight: HrisType.semibold, height: 1.2),
      iconTheme: IconThemeData(color: t.muted),
      actionsIconTheme: IconThemeData(color: t.muted),
    ),
    // The bottom tabs in the sidebar's clothes: active = primary-soft + primary.
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: t.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      indicatorColor: t.primarySoft,
      indicatorShape: RoundedRectangleBorder(borderRadius: radiusSm),
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? t.primary : t.muted, size: 24),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? ts(HrisType.xs, weight: HrisType.semibold, height: 1.2, color: t.primary)
            : ts(HrisType.xs, weight: FontWeight.w500, height: 1.2, color: t.muted),
      ),
      overlayColor: WidgetStatePropertyAll(t.hover),
    ),
    cardTheme: CardThemeData(
      color: t.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: radiusMd, side: BorderSide(color: t.border)),
    ),
    // Inputs sit RECESSED on a card (fill = page colour), like the web's.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.bg,
      border: OutlineInputBorder(borderRadius: radiusSm, borderSide: BorderSide(color: t.border)),
      enabledBorder: OutlineInputBorder(borderRadius: radiusSm, borderSide: BorderSide(color: t.border)),
      focusedBorder: OutlineInputBorder(borderRadius: radiusSm, borderSide: BorderSide(color: t.primary, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: radiusSm, borderSide: BorderSide(color: t.danger.border)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: radiusSm, borderSide: BorderSide(color: t.danger.solid, width: 2)),
      disabledBorder: OutlineInputBorder(borderRadius: radiusSm, borderSide: BorderSide(color: t.border)),
      contentPadding: const EdgeInsets.all(HrisSpace.s3),
      labelStyle: ts(HrisType.xs, weight: HrisType.semibold, height: 1.2, color: t.muted),
      floatingLabelStyle: ts(HrisType.xs, weight: HrisType.semibold, height: 1.2, color: t.muted),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      hintStyle: ts(HrisType.md, color: t.muted),
      helperStyle: ts(HrisType.xs, height: 1.3, color: t.muted),
      errorStyle: ts(HrisType.xs, height: 1.3, color: t.danger.text),
      prefixIconColor: t.muted,
      suffixIconColor: t.muted,
    ),
    // Button.module.css .primary — shared by FilledButton and FilledButton.tonal;
    // the secondary look for a tonal button is a call-site style (button_styles.dart).
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(primaryBg),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? t.primaryContrast.withValues(alpha: 0.9) : t.primaryContrast,
        ),
        iconColor: WidgetStatePropertyAll(t.primaryContrast),
        overlayColor: WidgetStatePropertyAll(Colors.white.withValues(alpha: 0.08)),
        textStyle: WidgetStatePropertyAll(buttonText),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: radiusSm)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: HrisSpace.s4, vertical: HrisSpace.s3)),
        minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
        elevation: const WidgetStatePropertyAll(0),
      ),
    ),
    // .secondary — surface, text colour, 1px border.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: t.surface,
        foregroundColor: t.text,
        disabledForegroundColor: t.text.withValues(alpha: 0.6),
        side: BorderSide(color: t.border),
        shape: RoundedRectangleBorder(borderRadius: radiusSm),
        textStyle: buttonText,
        padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s4, vertical: HrisSpace.s3),
        minimumSize: const Size(64, 48),
        overlayColor: t.hover,
      ),
    ),
    // .ghost — transparent, text colour (not primary).
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.text,
        disabledForegroundColor: t.text.withValues(alpha: 0.6),
        shape: RoundedRectangleBorder(borderRadius: radiusSm),
        textStyle: ts(HrisType.sm, weight: HrisType.semibold, height: 1.2),
        padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s3, vertical: HrisSpace.s2),
        overlayColor: t.hover,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: t.muted,
        disabledForegroundColor: t.muted.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(borderRadius: radiusSm),
        overlayColor: t.hover,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.primarySoft : t.surface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.primary : t.text,
        ),
        iconColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.primary : t.muted,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: t.border)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: radiusSm)),
        textStyle: WidgetStatePropertyAll(ts(HrisType.sm, weight: HrisType.semibold, height: 1.2)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: HrisSpace.s3, vertical: HrisSpace.s2)),
        overlayColor: WidgetStatePropertyAll(t.hover),
        visualDensity: VisualDensity.compact,
      ),
    ),
    // Safety net for any stray Chip; the screens use StatusBadge.
    chipTheme: ChipThemeData(
      backgroundColor: Color.alphaBlend(t.hover, t.surface),
      side: BorderSide(color: t.border),
      shape: const StadiumBorder(),
      labelStyle: ts(HrisType.xxs, weight: HrisType.semibold, height: 1.4, color: t.muted),
      padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s3, vertical: HrisSpace.s1),
      labelPadding: EdgeInsets.zero,
      showCheckmark: false,
    ),
    dividerTheme: DividerThemeData(color: t.border, thickness: 1, space: 1),
    // ConfirmDialog.module.css: surface, radius 14, no border, muted message.
    dialogTheme: DialogThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: radiusMd),
      titleTextStyle: ts(HrisType.lg, weight: HrisType.semibold, height: 1.3),
      contentTextStyle: ts(HrisType.sm, color: t.muted),
      actionsPadding: const EdgeInsets.fromLTRB(HrisSpace.s5, 0, HrisSpace.s5, HrisSpace.s5),
      insetPadding: const EdgeInsets.all(HrisSpace.s4),
      barrierColor: t.overlay,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(HrisRadius.md))),
      dragHandleColor: t.border,
      modalBarrierColor: t.overlay,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.surface,
      contentTextStyle: ts(HrisType.sm),
      shape: RoundedRectangleBorder(borderRadius: radiusSm, side: BorderSide(color: t.border)),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: ts(HrisType.md, height: 1.3),
      subtitleTextStyle: ts(HrisType.xs, height: 1.3, color: t.muted),
      iconColor: t.muted,
      contentPadding: const EdgeInsets.symmetric(horizontal: HrisSpace.s4, vertical: HrisSpace.s1),
      minVerticalPadding: 10,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.primary : t.border),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: t.primary,
      linearTrackColor: t.border,
      circularTrackColor: Colors.transparent,
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: radiusMd),
      headerForegroundColor: t.text,
    ),
  );
}
