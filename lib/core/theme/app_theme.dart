// lib/core/theme/app_theme.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  // ══════════════════════════════════════════════════════════════════════════
  // darkMSAL — фирменная тема приложения (бирюзовый на чёрном, по логотипу)
  // ══════════════════════════════════════════════════════════════════════════

  static const Color _msalBg       = Color(0xFF0D0B14);
  static const Color _msalCard     = Color(0xFF161320);
  static const Color _msalSurface  = Color(0xFF1C182A);
  static const Color _msalAccent   = Color(0xFF9C6FFF);
  static const Color _msalAccentSoft = Color(0xFFBE93FF);
  static const Color _msalNeon     = Color(0xFFD0B3FF);
  static const Color _msalTextPrim = Color(0xFFF0EBF8);
  static const Color _msalTextSec  = Color(0xFF9B8DB8);
  static const Color _msalTextMute = Color(0xFF5E5178);
  static const Color _msalDivider  = Color(0xFF231E33);

  // ══════════════════════════════════════════════════════════════════════════
  // МГЮА Dark — тёмно-синий / красный / белый (официальные цвета МГЮА)
  // ══════════════════════════════════════════════════════════════════════════

  static const Color _mguaBg       = Color(0xFF0F1724);
  static const Color _mguaCard     = Color(0xFF162036);
  static const Color _mguaSurface  = Color(0xFF1E2C4A);
  static const Color _mguaAccent   = Color(0xFFC62828);
  static const Color _mguaNeon     = Color(0xFFEF5350);
  static const Color _mguaTextPrim = Color(0xFFF0F0F5);
  static const Color _mguaTextSec  = Color(0xFF8A9BBE);
  static const Color _mguaTextMute = Color(0xFF4A5E82);
  static const Color _mguaDivider  = Color(0xFF243050);

  // ══════════════════════════════════════════════════════════════════════════
  // Shared colors
  // ══════════════════════════════════════════════════════════════════════════

  static const Color success = Color(0xFF4CAF82);
  static const Color warning = Color(0xFFFFB547);
  static const Color error   = Color(0xFFFF5C7C);

  // ── Static accessors for existing code that references AppTheme.xxx ─────
  // These point to the darkMSAL palette (default theme) for backward compat.
  static const Color bgDark       = _msalBg;
  static const Color bgCard       = _msalCard;
  static const Color bgSurface    = _msalSurface;
  static const Color accent       = _msalAccent;
  static const Color accentSoft   = _msalAccentSoft;
  static const Color neon         = _msalNeon;
  static const Color textPrimary  = _msalTextPrim;
  static const Color textSecondary = _msalTextSec;
  static const Color textMuted    = _msalTextMute;
  static const Color divider      = _msalDivider;

  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFF9C6FFF), Color(0xFFBE93FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF1C1C24), Color(0xFF141419)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient dangerGradient = LinearGradient(
    colors: [Color(0xFF4A1030), Color(0xFF2A0820)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ══════════════════════════════════════════════════════════════════════════
  // Theme builders
  // ══════════════════════════════════════════════════════════════════════════

  // ── darkMSAL (фирменная) ───────────────────────────────────────────────
  static ThemeData get darkMsal => _buildDark(
    bg: _msalBg,
    card: _msalCard,
    surface: _msalSurface,
    accent: _msalAccent,
    neon: _msalNeon,
    textPrim: _msalTextPrim,
    textSec: _msalTextSec,
    textMute: _msalTextMute,
    divider: _msalDivider,
  );

  // ── МГЮА Dark ──────────────────────────────────────────────────────────
  static ThemeData get darkMgua => _buildDark(
    bg: _mguaBg,
    card: _mguaCard,
    surface: _mguaSurface,
    accent: _mguaAccent,
    neon: _mguaNeon,
    textPrim: _mguaTextPrim,
    textSec: _mguaTextSec,
    textMute: _mguaTextMute,
    divider: _mguaDivider,
  );

  // ── МГЮА Light ─────────────────────────────────────────────────────────
  static ThemeData get lightMgua {
    final base = ThemeData.light(useMaterial3: true);
    const accentColor = Color(0xFFC62828);
    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFFF5F5F7),
      colorScheme: const ColorScheme.light(
        primary: accentColor,
        secondary: Color(0xFFEF5350),
        surface: Colors.white,
        error: error,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          color: const Color(0xFF1A2744),
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: const IconThemeData(color: Color(0xFF4A5E82)),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: accentColor.withOpacity(0.12),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.inter(
              color: accentColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            );
          }
          return GoogleFonts.inter(color: const Color(0xFF9E9E9E), fontSize: 11);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: accentColor, size: 22);
          }
          return const IconThemeData(color: Color(0xFF9E9E9E), size: 22);
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF0F0F2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accentColor, width: 1.5),
        ),
        labelStyle: GoogleFonts.inter(color: const Color(0xFF9E9E9E)),
        hintStyle: GoogleFonts.inter(color: const Color(0xFF9E9E9E)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFF0F0F2),
        labelStyle: GoogleFonts.inter(color: const Color(0xFF666666), fontSize: 12),
        side: BorderSide(color: Colors.grey.shade300),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dividerTheme: DividerThemeData(color: Colors.grey.shade200, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF323232),
        contentTextStyle: GoogleFonts.inter(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      drawerTheme: const DrawerThemeData(backgroundColor: Colors.white),
    );
  }

  // ── Custom theme ────────────────────────────────────────────────────────
  static ThemeData custom({
    required Color primary,
    required Color accent,
    required Color background,
  }) {
    // Derive palette from user colors
    final hsl = HSLColor.fromColor(background);
    final isDark = hsl.lightness < 0.5;

    if (isDark) {
      final card = HSLColor.fromAHSL(1, hsl.hue, hsl.saturation.clamp(0, 0.3),
              (hsl.lightness + 0.06).clamp(0, 1))
          .toColor();
      final surface = HSLColor.fromAHSL(1, hsl.hue,
              hsl.saturation.clamp(0, 0.3),
              (hsl.lightness + 0.1).clamp(0, 1))
          .toColor();
      final textPrim = isDark ? const Color(0xFFF0EBF8) : const Color(0xFF1A1A2E);
      final textSec = isDark ? const Color(0xFF9B8DB8) : const Color(0xFF666680);
      final textMute = isDark ? const Color(0xFF5E5178) : const Color(0xFF9E9EB0);
      final div = isDark
          ? HSLColor.fromAHSL(1, hsl.hue, hsl.saturation.clamp(0, 0.25),
                  (hsl.lightness + 0.12).clamp(0, 1))
              .toColor()
          : Colors.grey.shade200;

      return _buildDark(
        bg: background,
        card: card,
        surface: surface,
        accent: accent,
        neon: accent.withOpacity(0.8),
        textPrim: textPrim,
        textSec: textSec,
        textMute: textMute,
        divider: div,
      );
    } else {
      // Light custom theme
      final base = ThemeData.light(useMaterial3: true);
      return base.copyWith(
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.light(
          primary: primary,
          secondary: accent,
          surface: Colors.white,
          error: error,
        ),
        textTheme: GoogleFonts.interTextTheme(base.textTheme),
        appBarTheme: AppBarTheme(
          backgroundColor: background,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: GoogleFonts.inter(
            color: const Color(0xFF1A1A2E),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
          iconTheme: IconThemeData(color: primary),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          margin: EdgeInsets.zero,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        dividerTheme: DividerThemeData(color: Colors.grey.shade200, thickness: 1),
        drawerTheme: DrawerThemeData(backgroundColor: background),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF323232),
          contentTextStyle: GoogleFonts.inter(color: Colors.white),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── Old API compat ──────────────────────────────────────────────────────
  static ThemeData get light => lightMgua;
  static ThemeData get dark => darkMsal;

  // ══════════════════════════════════════════════════════════════════════════
  // Private dark theme builder (shared by darkMsal, darkMgua, custom-dark)
  // ══════════════════════════════════════════════════════════════════════════

  static ThemeData _buildDark({
    required Color bg,
    required Color card,
    required Color surface,
    required Color accent,
    required Color neon,
    required Color textPrim,
    required Color textSec,
    required Color textMute,
    required Color divider,
  }) {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.dark(
        primary: accent,
        secondary: neon,
        surface: card,
        error: error,
        onPrimary: Colors.white,
        onSecondary: Colors.black,
        onSurface: textPrim,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        displayLarge: GoogleFonts.inter(
          color: textPrim, fontSize: 32, fontWeight: FontWeight.w700,
        ),
        headlineMedium: GoogleFonts.inter(
          color: textPrim, fontSize: 22, fontWeight: FontWeight.w600,
        ),
        titleLarge: GoogleFonts.inter(
          color: textPrim, fontSize: 17, fontWeight: FontWeight.w600,
        ),
        titleMedium: GoogleFonts.inter(
          color: textPrim, fontSize: 15, fontWeight: FontWeight.w500,
        ),
        bodyLarge: GoogleFonts.inter(color: textSec, fontSize: 15),
        bodyMedium: GoogleFonts.inter(color: textSec, fontSize: 13),
        labelSmall: GoogleFonts.inter(color: textMute, fontSize: 11),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: divider, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          color: textPrim, fontSize: 18, fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: textSec),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: card,
        indicatorColor: accent.withOpacity(0.2),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.inter(
              color: accent, fontSize: 11, fontWeight: FontWeight.w600,
            );
          }
          return GoogleFonts.inter(color: textMute, fontSize: 11);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: accent, size: 22);
          }
          return IconThemeData(color: textMute, size: 22);
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        labelStyle: GoogleFonts.inter(color: textMute),
        hintStyle: GoogleFonts.inter(color: textMute),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15, fontWeight: FontWeight.w600,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        labelStyle: GoogleFonts.inter(color: textSec, fontSize: 12),
        side: BorderSide(color: divider),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dividerTheme: DividerThemeData(color: divider, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: GoogleFonts.inter(color: textPrim),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
