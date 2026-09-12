import 'package:flutter/material.dart';

/// The web HRIS design tokens (client/src/styles/tokens.css), verbatim, so the
/// phone and the website are the same product to look at. Two sets — the
/// `:root` light values and the `prefers-color-scheme: dark` ones — carried as
/// a ThemeExtension so any widget can read the colour the web would use.
///
/// Read them through [HrisTokens.of], never `extension<HrisTokens>()!`: several
/// widget tests mount screens under a bare MaterialApp with no theme, and the
/// accessor falls back by brightness so those keep working.
class HrisTokens extends ThemeExtension<HrisTokens> {
  final Color bg; // --color-bg (the page)
  final Color surface; // --color-surface (cards, bars)
  final Color text; // --color-text
  final Color muted; // --color-muted
  final Color border; // --color-border
  final Color primary; // --color-primary
  final Color primaryHover; // --color-primary-hover
  final Color primaryContrast; // --color-primary-contrast
  final Color primarySoft; // --color-primary-soft (active nav, focus ring)
  final Color hover; // --color-hover (neutral tint)
  final Color overlay; // --color-overlay (modal barrier)
  final StatusSet danger;
  final StatusSet success;
  final StatusSet warning;
  final StatusSet info;
  final BoxShadow shadowCard; // --shadow-card

  const HrisTokens({
    required this.bg,
    required this.surface,
    required this.text,
    required this.muted,
    required this.border,
    required this.primary,
    required this.primaryHover,
    required this.primaryContrast,
    required this.primarySoft,
    required this.hover,
    required this.overlay,
    required this.danger,
    required this.success,
    required this.warning,
    required this.info,
    required this.shadowCard,
  });

  static const light = HrisTokens(
    bg: Color(0xFFF1F5F9),
    surface: Color(0xFFFFFFFF),
    text: Color(0xFF0F172A),
    muted: Color(0xFF64748B),
    border: Color(0xFFE2E8F0),
    primary: Color(0xFF2563EB),
    primaryHover: Color(0xFF1D4ED8),
    primaryContrast: Color(0xFFFFFFFF),
    primarySoft: Color.fromRGBO(37, 99, 235, 0.10),
    hover: Color.fromRGBO(15, 23, 42, 0.04),
    overlay: Color.fromRGBO(2, 6, 23, 0.40),
    danger: StatusSet(bg: Color(0xFFFEF2F2), border: Color(0xFFFECACA), text: Color(0xFFB91C1C), solid: Color(0xFFDC2626)),
    success: StatusSet(bg: Color(0xFFF0FDF4), border: Color(0xFFBBF7D0), text: Color(0xFF15803D), solid: Color(0xFF16A34A)),
    // The web has no solid warning colour; the text colour stands in for accents.
    warning: StatusSet(bg: Color(0xFFFFFBEB), border: Color(0xFFFDE68A), text: Color(0xFFB45309), solid: Color(0xFFB45309)),
    info: StatusSet(bg: Color(0xFFEFF6FF), border: Color(0xFFBFDBFE), text: Color(0xFF1D4ED8), solid: Color(0xFF2563EB)),
    shadowCard: BoxShadow(color: Color.fromRGBO(2, 6, 23, 0.08), offset: Offset(0, 10), blurRadius: 30),
  );

  static const dark = HrisTokens(
    bg: Color(0xFF0F172A),
    surface: Color(0xFF1E293B),
    text: Color(0xFFE2E8F0),
    muted: Color(0xFF94A3B8),
    border: Color(0xFF334155),
    primary: Color(0xFF3B82F6),
    primaryHover: Color(0xFF2563EB),
    primaryContrast: Color(0xFFFFFFFF),
    primarySoft: Color.fromRGBO(59, 130, 246, 0.15),
    hover: Color.fromRGBO(255, 255, 255, 0.05),
    overlay: Color.fromRGBO(0, 0, 0, 0.55),
    danger: StatusSet(bg: Color(0xFF3B1D1D), border: Color(0xFF7F1D1D), text: Color(0xFFFCA5A5), solid: Color(0xFFDC2626)),
    success: StatusSet(bg: Color(0xFF14321F), border: Color(0xFF166534), text: Color(0xFF86EFAC), solid: Color(0xFF22C55E)),
    warning: StatusSet(bg: Color(0xFF3A2C12), border: Color(0xFF854D0E), text: Color(0xFFFCD34D), solid: Color(0xFFFCD34D)),
    info: StatusSet(bg: Color(0xFF172554), border: Color(0xFF1E40AF), text: Color(0xFF93C5FD), solid: Color(0xFF3B82F6)),
    shadowCard: BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.40), offset: Offset(0, 10), blurRadius: 30),
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
    Color? text,
    Color? muted,
    Color? border,
    Color? primary,
    Color? primaryHover,
    Color? primaryContrast,
    Color? primarySoft,
    Color? hover,
    Color? overlay,
    StatusSet? danger,
    StatusSet? success,
    StatusSet? warning,
    StatusSet? info,
    BoxShadow? shadowCard,
  }) =>
      HrisTokens(
        bg: bg ?? this.bg,
        surface: surface ?? this.surface,
        text: text ?? this.text,
        muted: muted ?? this.muted,
        border: border ?? this.border,
        primary: primary ?? this.primary,
        primaryHover: primaryHover ?? this.primaryHover,
        primaryContrast: primaryContrast ?? this.primaryContrast,
        primarySoft: primarySoft ?? this.primarySoft,
        hover: hover ?? this.hover,
        overlay: overlay ?? this.overlay,
        danger: danger ?? this.danger,
        success: success ?? this.success,
        warning: warning ?? this.warning,
        info: info ?? this.info,
        shadowCard: shadowCard ?? this.shadowCard,
      );

  @override
  HrisTokens lerp(HrisTokens? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return HrisTokens(
      bg: c(bg, other.bg),
      surface: c(surface, other.surface),
      text: c(text, other.text),
      muted: c(muted, other.muted),
      border: c(border, other.border),
      primary: c(primary, other.primary),
      primaryHover: c(primaryHover, other.primaryHover),
      primaryContrast: c(primaryContrast, other.primaryContrast),
      primarySoft: c(primarySoft, other.primarySoft),
      hover: c(hover, other.hover),
      overlay: c(overlay, other.overlay),
      danger: danger.lerp(other.danger, t),
      success: success.lerp(other.success, t),
      warning: warning.lerp(other.warning, t),
      info: info.lerp(other.info, t),
      shadowCard: BoxShadow.lerp(shadowCard, other.shadowCard, t)!,
    );
  }
}

/// One status colour family: the soft background, its border, the text that
/// sits on it, and the solid accent (badges, banners, verdict pills).
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

/// --space-1 … --space-6
abstract final class HrisSpace {
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 24.0;
  static const s6 = 32.0;
}

/// --radius-sm / --radius-md / --radius-pill
abstract final class HrisRadius {
  static const sm = 8.0;
  static const md = 14.0;
  static const pill = 999.0;
}

/// The web type scale at a 16px root, in logical pixels.
abstract final class HrisType {
  static const xxs = 11.52; // --fs-2xs
  static const xs = 13.12; // --fs-xs
  static const sm = 14.4; // --fs-sm
  static const md = 15.2; // --fs-md
  static const lg = 20.0; // --fs-lg
  static const heading = 22.4; // --fs-heading
  static const stat = 28.8; // --fs-stat
  static const xl = 30.4; // --fs-xl
  static const semibold = FontWeight.w600; // --fw-semibold
}

/// Fixed chrome sizes from the web shell.
abstract final class HrisSize {
  static const topBar = 60.0; // --header-height
  static const avatar = 32.0; // the top-bar avatar
  static const brandDot = 10.0; // .brandDot
}
