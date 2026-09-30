import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// The app's Material 3 theme built from the web HRIS tokens ("Petrol & Paper")
/// — one for each brightness, so the phone follows the system dark mode exactly
/// as the website follows `prefers-color-scheme`. Every component theme below
/// maps a web CSS module (Button, Input, Badge, Dialog, Toast, SectionTabs …)
/// onto its Material counterpart; screens then need little or no per-widget
/// styling.
///
/// Phone sizing (the web's own ≤640px rules, not its 32px desktop density):
/// controls are DRAWN 44px high but every tap target is at least 48dp
/// (MaterialTapTargetSize.padded); body text is never below 14.
/// The Android status and navigation bars in the web page colour, with icons
/// that read on it. Used by the app bar and, for pages without one, by the
/// app root.
SystemUiOverlayStyle hrisSystemUi(Brightness brightness) {
  final t = brightness == Brightness.dark ? HrisTokens.dark : HrisTokens.light;
  final icons = brightness == Brightness.dark ? Brightness.light : Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: icons,
    statusBarBrightness: brightness,
    systemNavigationBarColor: t.bg,
    systemNavigationBarIconBrightness: icons,
    systemNavigationBarDividerColor: t.border,
  );
}

ThemeData buildTheme([Brightness brightness = Brightness.light]) {
  final t = brightness == Brightness.dark ? HrisTokens.dark : HrisTokens.light;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: t.primary,
    onPrimary: t.primaryContrast,
    primaryContainer: t.primarySoft,
    onPrimaryContainer: t.primaryText,
    secondary: t.text2,
    onSecondary: t.surface,
    // Tonal buttons, selected segments and the nav indicator default to the
    // secondary container: primary-soft + petrol text gives the web's active look.
    secondaryContainer: t.primarySoft,
    onSecondaryContainer: t.primaryText,
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
    onSurfaceVariant: t.text2,
    surfaceDim: t.bg,
    surfaceBright: t.surface,
    surfaceContainerLowest: t.surface,
    surfaceContainerLow: t.surface,
    surfaceContainer: t.surfaceSunken,
    surfaceContainerHigh: t.surface,
    surfaceContainerHighest: t.hover,
    outline: t.borderStrong,
    outlineVariant: t.border,
    inverseSurface: t.text,
    onInverseSurface: t.surface,
    inversePrimary: t.primarySoft,
    shadow: Colors.black,
    scrim: t.overlay,
    // No M3 tint overlays anywhere: the web's surfaces are flat.
    surfaceTint: Colors.transparent,
  );

  // `lh` is the web line height in px; Flutter wants a multiple of the size.
  TextStyle ts(double size, double lh, {FontWeight weight = FontWeight.w400, Color? color}) => TextStyle(
        fontFamily: HrisFont.sans,
        fontSize: size,
        fontWeight: weight,
        height: lh / size,
        color: color ?? t.text,
        letterSpacing: 0,
      );

  final textTheme = TextTheme(
    displaySmall: ts(HrisType.stat, 32, weight: HrisType.semibold), // figures
    headlineMedium: ts(HrisType.xl, 32, weight: HrisType.semibold),
    headlineSmall: ts(HrisType.stat, 32, weight: HrisType.semibold), // KPI / login title
    titleLarge: ts(HrisType.heading, 28, weight: HrisType.semibold), // page title (h1)
    titleMedium: ts(HrisType.md, 24, weight: HrisType.semibold), // section / dialog title
    titleSmall: ts(HrisType.sm, 20, weight: HrisType.semibold), // emphasised body
    bodyLarge: ts(HrisType.md, 24), // large body, input text
    bodyMedium: ts(HrisType.sm, 20), // body
    bodySmall: ts(HrisType.xs, 16, color: t.text2), // captions, meta
    labelLarge: ts(HrisType.sm, 20, weight: HrisType.medium), // buttons
    labelMedium: ts(HrisType.xs, 16, weight: HrisType.medium, color: t.text2), // field labels, headers
    labelSmall: ts(HrisType.xxs, 16, weight: HrisType.medium, color: t.text2), // badges
  );

  final rControl = BorderRadius.circular(HrisRadius.control);
  final rPanel = BorderRadius.circular(HrisRadius.panel);
  final buttonText = ts(HrisType.sm, 20, weight: HrisType.medium);
  const buttonPadding = EdgeInsets.symmetric(horizontal: HrisSpace.s4, vertical: HrisSpace.s3);
  const buttonMin = Size(64, HrisSize.control);

  Color primaryBg(Set<WidgetState> s) {
    if (s.contains(WidgetState.disabled)) return t.surfaceSunken;
    if (s.contains(WidgetState.pressed)) return t.primaryHover;
    return t.primary;
  }

  OutlineInputBorder field(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: rControl, borderSide: BorderSide(color: c, width: w));

  return ThemeData(
    useMaterial3: true,
    fontFamily: HrisFont.sans,
    colorScheme: scheme,
    extensions: [t],
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.surface,
    dividerColor: t.border,
    hoverColor: t.hover,
    highlightColor: t.hover,
    splashColor: t.hover,
    focusColor: t.primarySoft,
    disabledColor: t.muted,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    iconTheme: IconThemeData(color: t.text2, size: 20),
    // The web top bar: surface, one hairline underneath, no shadow.
    appBarTheme: AppBarTheme(
      backgroundColor: t.surface,
      foregroundColor: t.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: HrisSize.topBar,
      shape: Border(bottom: BorderSide(color: t.border)),
      titleSpacing: HrisSpace.s4,
      centerTitle: false,
      titleTextStyle: ts(HrisType.md, 24, weight: HrisType.semibold),
      iconTheme: IconThemeData(color: t.text2, size: 22),
      actionsIconTheme: IconThemeData(color: t.text2, size: 22),
      systemOverlayStyle: hrisSystemUi(brightness),
    ),
    // The web sidebar, as a drawer: nav-bg (the sunken surface), square edge.
    drawerTheme: DrawerThemeData(
      backgroundColor: t.surfaceSunken,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(),
      scrimColor: t.overlay,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: t.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      indicatorColor: t.primarySoft,
      indicatorShape: RoundedRectangleBorder(borderRadius: rControl),
      height: 64,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? t.primaryText : t.text2, size: 22),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? ts(HrisType.xs, 16, weight: HrisType.semibold, color: t.primaryText)
            : ts(HrisType.xs, 16, weight: HrisType.medium, color: t.text2),
      ),
      overlayColor: WidgetStatePropertyAll(t.hover),
    ),
    // Panels: surface, 1px border, radius 6, no shadow.
    cardTheme: CardThemeData(
      color: t.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: rPanel, side: BorderSide(color: t.border)),
    ),
    // Input.module.css: surface fill, 1px border-strong, radius 4; focus = petrol
    // edge + 1px ring (drawn as a 2px focus border here).
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.surface,
      isDense: false,
      border: field(t.borderStrong),
      enabledBorder: field(t.borderStrong),
      focusedBorder: field(t.focus, 2),
      errorBorder: field(t.danger.text),
      focusedErrorBorder: field(t.danger.text, 2),
      disabledBorder: field(t.border),
      contentPadding: const EdgeInsets.symmetric(horizontal: HrisSpace.s3, vertical: HrisSpace.s3),
      labelStyle: ts(HrisType.sm, 20, weight: HrisType.medium, color: t.text2),
      floatingLabelStyle: WidgetStateTextStyle.resolveWith(
        (s) => ts(HrisType.sm, 20,
            weight: HrisType.medium,
            color: s.contains(WidgetState.error) ? t.danger.text : (s.contains(WidgetState.focused) ? t.primaryText : t.text)),
      ),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      hintStyle: ts(HrisType.sm, 20, color: t.muted),
      helperStyle: ts(HrisType.xs, 16, color: t.muted),
      errorStyle: ts(HrisType.xs, 16, color: t.danger.text),
      prefixIconColor: t.muted,
      suffixIconColor: t.muted,
    ),
    // Button.module.css .primary — petrol fill, white text, radius 4. Disabled is
    // the web's sunken fill with muted text (not a faded petrol).
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(primaryBg),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? t.muted : t.primaryContrast,
        ),
        iconColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? t.muted : t.primaryContrast,
        ),
        side: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? BorderSide(color: t.border) : BorderSide.none,
        ),
        overlayColor: WidgetStatePropertyAll(Colors.white.withValues(alpha: 0.08)),
        textStyle: WidgetStatePropertyAll(buttonText),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: rControl)),
        padding: const WidgetStatePropertyAll(buttonPadding),
        minimumSize: const WidgetStatePropertyAll(buttonMin),
        elevation: const WidgetStatePropertyAll(0),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),
    // .secondary — surface, text colour, 1px border-strong.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: t.surface,
        foregroundColor: t.text,
        disabledForegroundColor: t.muted,
        disabledBackgroundColor: t.surfaceSunken,
        side: BorderSide(color: t.borderStrong),
        shape: RoundedRectangleBorder(borderRadius: rControl),
        textStyle: buttonText,
        padding: buttonPadding,
        minimumSize: buttonMin,
        overlayColor: t.hover,
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),
    // .ghost — transparent, text colour.
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.text,
        disabledForegroundColor: t.muted,
        shape: RoundedRectangleBorder(borderRadius: rControl),
        textStyle: buttonText,
        padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s3, vertical: HrisSpace.s2),
        minimumSize: const Size(48, HrisSize.control),
        overlayColor: t.hover,
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: t.text2,
        disabledForegroundColor: t.muted,
        shape: RoundedRectangleBorder(borderRadius: rControl),
        overlayColor: t.hover,
        minimumSize: const Size(HrisSize.touch, HrisSize.touch),
      ),
    ),
    // ViewToggle: selected = primary-soft + petrol text; square-ish (radius 4).
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.primarySoft : t.surface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.primaryText : t.text,
        ),
        iconColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.primaryText : t.text2,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: t.borderStrong)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: rControl)),
        textStyle: WidgetStatePropertyAll(ts(HrisType.sm, 20, weight: HrisType.medium)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: HrisSpace.s3, vertical: HrisSpace.s2)),
        minimumSize: const WidgetStatePropertyAll(Size(48, HrisSize.control)),
        overlayColor: WidgetStatePropertyAll(t.hover),
        visualDensity: VisualDensity.standard,
      ),
    ),
    // SectionTabs: text tabs with a 2px petrol underline on the active one.
    tabBarTheme: TabBarThemeData(
      labelColor: t.text,
      unselectedLabelColor: t.text2,
      labelStyle: ts(HrisType.sm, 20, weight: HrisType.semibold),
      unselectedLabelStyle: ts(HrisType.sm, 20, weight: HrisType.medium),
      indicatorColor: t.primary,
      indicatorSize: TabBarIndicatorSize.tab,
      indicator: UnderlineTabIndicator(borderSide: BorderSide(color: t.primary, width: 2)),
      dividerColor: t.border,
      dividerHeight: 1,
      overlayColor: WidgetStatePropertyAll(t.hover),
    ),
    // A stray Chip reads as a web tag: square, sunken, 12px.
    chipTheme: ChipThemeData(
      backgroundColor: t.neutral.bg,
      side: BorderSide(color: t.neutral.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HrisRadius.badge)),
      labelStyle: ts(HrisType.xxs, 16, weight: HrisType.medium, color: t.neutral.text),
      padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s2, vertical: 2),
      labelPadding: EdgeInsets.zero,
      showCheckmark: false,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? (s.contains(WidgetState.disabled) ? t.muted : t.primary)
            : t.surface,
      ),
      checkColor: WidgetStatePropertyAll(t.primaryContrast),
      side: WidgetStateBorderSide.resolveWith(
        (s) => BorderSide(color: s.contains(WidgetState.selected) ? Colors.transparent : t.borderStrong),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HrisRadius.badge)),
      overlayColor: WidgetStatePropertyAll(t.primarySoft),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.primary : t.borderStrong),
      overlayColor: WidgetStatePropertyAll(t.primarySoft),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.primary : t.borderStrong),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    dividerTheme: DividerThemeData(color: t.border, thickness: 1, space: 1),
    // Dialog.module.css / ConfirmDialog: surface, radius 6, 1px border, overlay shadow.
    dialogTheme: DialogThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: brightness == Brightness.dark ? 0.5 : 0.12),
      shape: RoundedRectangleBorder(borderRadius: rPanel, side: BorderSide(color: t.border)),
      titleTextStyle: ts(HrisType.md, 24, weight: HrisType.semibold),
      contentTextStyle: ts(HrisType.sm, 20, color: t.text2),
      actionsPadding: const EdgeInsets.fromLTRB(HrisSpace.s4, 0, HrisSpace.s4, HrisSpace.s4),
      insetPadding: const EdgeInsets.all(HrisSpace.s4),
      barrierColor: t.overlay,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(HrisRadius.panel)),
        side: BorderSide(color: t.border),
      ),
      dragHandleColor: t.borderStrong,
      modalBarrierColor: t.overlay,
    ),
    // Toast.module.css: surface, 1px border, radius 6, text colour.
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.surface,
      contentTextStyle: ts(HrisType.sm, 20),
      actionTextColor: t.primaryText,
      shape: RoundedRectangleBorder(borderRadius: rPanel, side: BorderSide(color: t.border)),
      behavior: SnackBarBehavior.floating,
      elevation: 4,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: t.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: rPanel, side: BorderSide(color: t.border)),
      textStyle: ts(HrisType.sm, 20),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: t.text, borderRadius: BorderRadius.circular(HrisRadius.control)),
      textStyle: ts(HrisType.xs, 16, color: t.surface),
    ),
    // Ruled-list rows: 48dp minimum, body title, caption subtitle.
    listTileTheme: ListTileThemeData(
      titleTextStyle: ts(HrisType.sm, 20),
      subtitleTextStyle: ts(HrisType.xs, 16, color: t.text2),
      leadingAndTrailingTextStyle: ts(HrisType.sm, 20, color: t.text2),
      iconColor: t.text2,
      selectedColor: t.primaryText,
      selectedTileColor: t.primarySoft,
      contentPadding: const EdgeInsets.symmetric(horizontal: HrisSpace.s4),
      minVerticalPadding: HrisSpace.s3,
      minTileHeight: HrisSize.touch,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: t.primary,
      linearTrackColor: t.border,
      circularTrackColor: Colors.transparent,
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: rPanel, side: BorderSide(color: t.border)),
      headerForegroundColor: t.text,
      dayShape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: rControl)),
      todayForegroundColor: WidgetStatePropertyAll(t.primaryText),
      todayBorder: BorderSide(color: t.primary),
    ),
  );
}
