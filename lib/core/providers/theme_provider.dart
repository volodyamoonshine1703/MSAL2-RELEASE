// lib/core/providers/theme_provider.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';

class AppThemeState {
  const AppThemeState();

  ThemeData get themeData {
    return AppTheme.custom(
      primary: const Color(0xFF9C6FFF),
      accent: const Color(0xFFBE93FF),
      background: const Color(0xFF0D0B14),
    );
  }

  ThemeMode get themeMode => ThemeMode.dark;
}

final appThemeProvider = Provider<AppThemeState>((ref) => const AppThemeState());
