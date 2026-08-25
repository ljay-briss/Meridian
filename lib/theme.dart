import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Theme extension so colors ride on Theme.of(context).
class AppColorsExt extends ThemeExtension<AppColorsExt> {
  final AppColors colors;
  const AppColorsExt(this.colors);
  @override
  ThemeExtension<AppColorsExt> copyWith() => this;
  @override
  ThemeExtension<AppColorsExt> lerp(ThemeExtension<AppColorsExt>? other, double t) => this;
}

/// Build a MaterialApp theme carrying our palette.
ThemeData appThemeData(AppColors c) {
  return ThemeData.dark().copyWith(
    scaffoldBackgroundColor: c.appBg,
    splashFactory: InkRipple.splashFactory,
    extensions: [AppColorsExt(c)],
  );
}

/// Design tokens — single near-black, monochrome "burner phone" palette.
class AppColors {
  /// Pull the active palette from context.
  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColorsExt>()!.colors;

  final Color appBg,
      surface,
      surfaceAlt,
      sunken,
      ink,
      inkSoft,
      inkFaint,
      line,
      lineSoft,
      primary,
      primaryInk,
      primarySoft,
      pos,
      neg,
      warn,
      chipBg,
      navBg,
      personalSurface,
      personalLine,
      personalDot;

  const AppColors({
    required this.appBg,
    required this.surface,
    required this.surfaceAlt,
    required this.sunken,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.line,
    required this.lineSoft,
    required this.primary,
    required this.primaryInk,
    required this.primarySoft,
    required this.pos,
    required this.neg,
    required this.warn,
    required this.chipBg,
    required this.navBg,
    required this.personalSurface,
    required this.personalLine,
    required this.personalDot,
  });

  factory AppColors.standard() => const AppColors(
        appBg: Color(0xFF050505),
        surface: Color(0xFF0A0A0A),
        surfaceAlt: Color(0xFF101010),
        sunken: Color(0xFF131313),
        ink: Color(0xFFF2F2F2),
        inkSoft: Color(0xFF9A9A9A),
        inkFaint: Color(0xFF666666),
        line: Color(0xFF1C1C1C),
        lineSoft: Color(0xFF141414),
        primary: Color(0xFFF2F2F2),
        primaryInk: Color(0xFF050505),
        primarySoft: Color(0xFF1E1E1E),
        pos: Color(0xFF4FC98A),
        neg: Color(0xFFE0685C),
        warn: Color(0xFFD9A84E),
        chipBg: Color(0xFF141414),
        navBg: Color(0xFF0A0A0A),
        // Warm-tinted grey — same near-black family as the cartel surfaces,
        // but R>G>B instead of neutral, so personal threads read differently
        // without breaking the monochrome look.
        personalSurface: Color(0xFF141210),
        personalLine: Color(0xFF241F1A),
        personalDot: Color(0xFFC9BBA6),
      );
}

/// Text helpers — IBM Plex Mono throughout, matching the burner-phone UI.
class AppText {
  static TextStyle sans({
    double size = 14,
    FontWeight weight = FontWeight.w500,
    Color? color,
    double? spacing,
    double? height,
  }) =>
      GoogleFonts.ibmPlexMono(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: spacing,
        height: height,
      );

  static TextStyle mono({
    double size = 14,
    FontWeight weight = FontWeight.w600,
    Color? color,
    double spacing = -0.2,
  }) =>
      GoogleFonts.ibmPlexMono(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: spacing,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Uppercase tracked label.
  static TextStyle label(Color color) => GoogleFonts.ibmPlexMono(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.8,
        color: color,
      );
}

/// ── Formatters ──────────────────────────────────────────────────────────
String _thousands(num n) {
  final s = n.round().abs().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

String money(num n) {
  final neg = n < 0;
  final body = '\$${_thousands(n.abs())}';
  return neg ? '-$body' : body;
}

String signedMoney(num n) => (n >= 0 ? '+' : '') + money(n);

Color riskColor(AppColors c, double risk) {
  if (risk < 20) return c.inkFaint;
  if (risk < 45) return c.pos;
  if (risk < 75) return c.warn;
  return c.neg;
}

String riskLabel(double risk) {
  if (risk < 20) return '—';
  if (risk < 45) return 'LOW';
  if (risk < 75) return 'ELEVATED';
  return 'HIGH';
}
