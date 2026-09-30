import 'package:flutter/material.dart';

/// The web HRIS design tokens — "Petrol & Paper" (hris/client/src/styles/
/// tokens.css) — verbatim, so the phone and the website are the same product to
/// look at. Two sets — the `:root` light values and the `[data-theme="dark"]`
/// ones — carried as a ThemeExtension so any widget can read the colour the web
/// would use.
///
/// Read them through [HrisTokens.of], never `extension<HrisTokens>()!`: several
/// widget tests mount screens under a bare MaterialApp with no theme, and the
/// accessor falls back by brightness so those keep working.
class HrisTokens extends ThemeExtension<HrisTokens> {
  final Color bg; // --bg (the page)
  final Color surface; // --surface (panels, bars, dialogs)
  final Color surfaceSunken; // --surface-sunken (input fill, list headers, drawer)
  final Color text; // --text
  final Color text2; // --text-2 (secondary text, captions, headers)
  final Color muted; // --muted (hints, meta, icons)
  final Color border; // --border (panel edges, dividers)
  final Color borderStrong; // --border-strong (control edges)
  final Color primary; // --primary (petrol fills and borders)
  final Color primaryHover; // --primary-hover
  final Color primaryContrast; // --primary-contrast
  final Color primarySoft; // --primary-soft (active nav, selected segment)
  final Color primaryText; // --primary-text (petrol as TEXT: link tint in dark)
  final Color focus; // --focus (focus ring)
  final Color hover; // --surface-hover (pressed / hover tint)
  final Color overlay; // --overlay (modal barrier)
  final Color skeleton; // --skeleton (loading placeholders)
  final Color countBg; // --count-bg (unread counts)
  final StatusSet danger;
  final StatusSet success;
  final StatusSet warning;
  final StatusSet info;
  final StatusSet neutral;
  // Panels carry no shadow on the web (borders over shadows); kept so existing
  // callers compile, and fully transparent.
  final BoxShadow shadowCard;
  final List<BoxShadow> shadowOverlay; // --shadow-overlay (menus, sheets only)

  const HrisTokens({
    required this.bg,
    required this.surface,
    required this.surfaceSunken,
    required this.text,
    required this.text2,
    required this.muted,
    required this.border,
    required this.borderStrong,
    required this.primary,
    required this.primaryHover,
    required this.primaryContrast,
    required this.primarySoft,
    required this.primaryText,
    required this.focus,
    required this.hover,
    required this.overlay,
    required this.skeleton,
    required this.countBg,
    required this.danger,
    required this.success,
    required this.warning,
    required this.info,
    required this.neutral,
    required this.shadowCard,
    required this.shadowOverlay,
  });

  static const light = HrisTokens(
    bg: Color(0xFFF7F7F6),
    surface: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFF7F7F6),
    text: Color(0xFF1B1F22),
    text2: Color(0xFF4F5559),
    muted: Color(0xFF676C70),
    border: Color(0xFFE3E1DA),
    borderStrong: Color(0xFFCBC8BF),
    primary: Color(0xFF0B5563),
    primaryHover: Color(0xFF084451),
    primaryContrast: Color(0xFFFFFFFF),
    primarySoft: Color(0xFFE3F0F1),
    primaryText: Color(0xFF0B5563),
    focus: Color(0xFF0B5563),
    hover: Color(0xFFEFEFEE),
    overlay: Color.fromRGBO(20, 30, 34, 0.40),
    skeleton: Color(0xFFEBEBEA),
    countBg: Color(0xFFD90B28),
    // `solid` is the colour a mark or a fill uses; the web has one hue per tone
    // (text and marker alike), plus a separate solid for destructive fills.
    danger: StatusSet(bg: Color(0xFFFEF3F2), border: Color(0xFFFECDCA), text: Color(0xFFB42318), solid: Color(0xFFB42318)),
    success: StatusSet(bg: Color(0xFFECFDF3), border: Color(0xFFABEFC6), text: Color(0xFF067647), solid: Color(0xFF067647)),
    warning: StatusSet(bg: Color(0xFFFFFAEB), border: Color(0xFFFEDF89), text: Color(0xFFB54708), solid: Color(0xFFB54708)),
    info: StatusSet(bg: Color(0xFFEFF8FF), border: Color(0xFFB2DDFF), text: Color(0xFF175CD3), solid: Color(0xFF175CD3)),
    neutral: StatusSet(bg: Color(0xFFEFEFEE), border: Color(0xFFD6D3CB), text: Color(0xFF4F5559), solid: Color(0xFF4F5559)),
    shadowCard: BoxShadow(color: Color(0x00000000)),
    shadowOverlay: [
      BoxShadow(color: Color.fromRGBO(20, 30, 34, 0.12), offset: Offset(0, 8), blurRadius: 24),
      BoxShadow(color: Color.fromRGBO(20, 30, 34, 0.08), offset: Offset(0, 1), blurRadius: 2),
    ],
  );

  static const dark = HrisTokens(
    bg: Color(0xFF0F1416),
    surface: Color(0xFF171C1E),
    surfaceSunken: Color(0xFF13181A),
    text: Color(0xFFE7ECEC),
    text2: Color(0xFFAAB4B6),
    muted: Color(0xFF8A9597),
    border: Color(0xFF283034),
    borderStrong: Color(0xFF37403F),
    primary: Color(0xFF137A8C),
    primaryHover: Color(0xFF1A8BA0),
    primaryContrast: Color(0xFFFFFFFF),
    primarySoft: Color(0xFF1B3236),
    primaryText: Color(0xFF5CC4D4),
    focus: Color(0xFF5CC4D4),
    hover: Color(0xFF1E2427),
    overlay: Color.fromRGBO(0, 0, 0, 0.60),
    skeleton: Color(0xFF1E2427),
    countBg: Color(0xFFD90B28),
    // Destructive fills stay the light red in dark too (white text on it passes).
    danger: StatusSet(bg: Color(0xFF2D1412), border: Color(0xFF7A271A), text: Color(0xFFFDA29B), solid: Color(0xFFB42318)),
    success: StatusSet(bg: Color(0xFF0B2A1C), border: Color(0xFF155E3B), text: Color(0xFF75E0A7), solid: Color(0xFF75E0A7)),
    warning: StatusSet(bg: Color(0xFF2E2210), border: Color(0xFF6B4A10), text: Color(0xFFFEC84B), solid: Color(0xFFFEC84B)),
    info: StatusSet(bg: Color(0xFF0F2440), border: Color(0xFF1F4F8F), text: Color(0xFF84CAFF), solid: Color(0xFF84CAFF)),
    neutral: StatusSet(bg: Color(0xFF1E2427), border: Color(0xFF37403F), text: Color(0xFFB7C2C4), solid: Color(0xFFB7C2C4)),
    shadowCard: BoxShadow(color: Color(0x00000000)),
    shadowOverlay: [
      BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.5), offset: Offset(0, 8), blurRadius: 24),
      BoxShadow(color: Color(0xFF37403F), spreadRadius: 1),
    ],
  );

  /// The tokens in force, with a brightness fallback for a theme-less tree.
  static HrisTokens of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<HrisTokens>() ?? (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  HrisTokens copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceSunken,
    Color? text,
    Color? text2,
    Color? muted,
    Color? border,
    Color? borderStrong,
    Color? primary,
    Color? primaryHover,
    Color? primaryContrast,
    Color? primarySoft,
    Color? primaryText,
    Color? focus,
    Color? hover,
    Color? overlay,
    Color? skeleton,
    Color? countBg,
    StatusSet? danger,
    StatusSet? success,
    StatusSet? warning,
    StatusSet? info,
    StatusSet? neutral,
    BoxShadow? shadowCard,
    List<BoxShadow>? shadowOverlay,
  }) =>
      HrisTokens(
        bg: bg ?? this.bg,
        surface: surface ?? this.surface,
        surfaceSunken: surfaceSunken ?? this.surfaceSunken,
        text: text ?? this.text,
        text2: text2 ?? this.text2,
        muted: muted ?? this.muted,
        border: border ?? this.border,
        borderStrong: borderStrong ?? this.borderStrong,
        primary: primary ?? this.primary,
        primaryHover: primaryHover ?? this.primaryHover,
        primaryContrast: primaryContrast ?? this.primaryContrast,
        primarySoft: primarySoft ?? this.primarySoft,
        primaryText: primaryText ?? this.primaryText,
        focus: focus ?? this.focus,
        hover: hover ?? this.hover,
        overlay: overlay ?? this.overlay,
        skeleton: skeleton ?? this.skeleton,
        countBg: countBg ?? this.countBg,
        danger: danger ?? this.danger,
        success: success ?? this.success,
        warning: warning ?? this.warning,
        info: info ?? this.info,
        neutral: neutral ?? this.neutral,
        shadowCard: shadowCard ?? this.shadowCard,
        shadowOverlay: shadowOverlay ?? this.shadowOverlay,
      );

  @override
  HrisTokens lerp(HrisTokens? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return HrisTokens(
      bg: c(bg, other.bg),
      surface: c(surface, other.surface),
      surfaceSunken: c(surfaceSunken, other.surfaceSunken),
      text: c(text, other.text),
      text2: c(text2, other.text2),
      muted: c(muted, other.muted),
      border: c(border, other.border),
      borderStrong: c(borderStrong, other.borderStrong),
      primary: c(primary, other.primary),
      primaryHover: c(primaryHover, other.primaryHover),
      primaryContrast: c(primaryContrast, other.primaryContrast),
      primarySoft: c(primarySoft, other.primarySoft),
      primaryText: c(primaryText, other.primaryText),
      focus: c(focus, other.focus),
      hover: c(hover, other.hover),
      overlay: c(overlay, other.overlay),
      skeleton: c(skeleton, other.skeleton),
      countBg: c(countBg, other.countBg),
      danger: danger.lerp(other.danger, t),
      success: success.lerp(other.success, t),
      warning: warning.lerp(other.warning, t),
      info: info.lerp(other.info, t),
      neutral: neutral.lerp(other.neutral, t),
      shadowCard: BoxShadow.lerp(shadowCard, other.shadowCard, t)!,
      shadowOverlay: BoxShadow.lerpList(shadowOverlay, other.shadowOverlay, t)!,
    );
  }
}

/// One status colour family: the soft background, its border, the text that
/// sits on it, and the solid accent (the square marker, a progress fill).
class StatusSet {
  final Color bg;
  final Color border;
  final Color text;
  final Color solid;

  const StatusSet({required this.bg, required this.border, required this.text, required this.solid});

  StatusSet lerp(StatusSet other, double t) => StatusSet(
        bg: Color.lerp(bg, other.bg, t)!,
        border: Color.lerp(border, other.border, t)!,
        text: Color.lerp(text, other.text, t)!,
        solid: Color.lerp(solid, other.solid, t)!,
      );
}

/// --space-1 … --space-8 (4px base).
abstract final class HrisSpace {
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 20.0;
  static const s6 = 24.0;
  static const s7 = 32.0;
  static const s8 = 40.0;
}

/// --r-2 / --r-4 / --r-6 — no pills except avatars (and the round count dot).
abstract final class HrisRadius {
  static const badge = 2.0; // badges, counts' square cousins, checkbox
  static const control = 4.0; // buttons, inputs, menu items
  static const panel = 6.0; // panels, dialogs, sheets, snackbars
  static const sm = control; // (former name) controls
  static const md = panel; // (former name) panels
  static const pill = 999.0; // avatars and the unread-count dot only
}

/// The families bundled in assets/fonts (IBM Plex, as the web).
abstract final class HrisFont {
  static const sans = 'IBMPlexSans';
  static const mono = 'IBMPlexMono';
}

/// The web type scale, adjusted for a phone: body never below 14, captions and
/// badges 12 (the only roles the web allows 12px for).
abstract final class HrisType {
  static const xxs = 12.0; // badges, counts (--fs-12)
  static const xs = 12.0; // captions, meta lines, table headers (--fs-12)
  static const sm = 14.0; // body (web body is 13; 14 is the phone minimum)
  static const md = 16.0; // large body, inputs, section titles (--fs-16)
  static const lg = 20.0; // top-bar title (--fs-20)
  static const heading = 20.0; // page title (h1, --fs-20)
  static const stat = 24.0; // figures (--fs-24)
  static const xl = 24.0; // the sign-in wordmark (--fs-24)
  static const clock = 36.0; // the Time Clock's live clock (the web portal clock)
  static const medium = FontWeight.w500; // --fw-medium
  static const semibold = FontWeight.w600; // --fw-semibold
}

/// Fixed chrome sizes.
abstract final class HrisSize {
  static const topBar = 56.0; // the web's 48px bar, grown to hold 48dp targets
  static const avatar = 32.0; // the top-bar avatar
  static const brandMark = 28.0; // the mark in the top bar (web BrandLogo lg)
  static const brandMarkAuth = 48.0; // the sign-in / splash mark
  static const control = 44.0; // drawn height of buttons and inputs
  static const touch = 48.0; // the smallest tap target
}

/// The web camera frame (CameraStage.module.css `--camera-bg`): one fixed dark
/// stage in both themes, so the preview never sits on a light box.
abstract final class HrisCamera {
  static const stage = Color(0xFF101416);
  // Text on the stage (--camera-ink / --camera-ink-2): fixed, since the stage
  // is dark in both themes.
  static const ink = Color(0xFFE7ECEC);
  static const ink2 = Color(0xFFC9D1D3);
}
