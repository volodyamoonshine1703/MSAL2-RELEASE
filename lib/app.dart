import 'core/providers.dart';
// lib/app.dart

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'presentation/screens/login/login_screen.dart';
import 'presentation/screens/shell/main_shell.dart';
import 'core/providers/theme_provider.dart';

// ── Session provider ──────────────────────────────────────────────────────────
// Strategy:
//   1. If we have a cached user + saved credentials → show app immediately,
//      refresh session in background (avoids startup hang on slow network)
//   2. If no cached user → try login with timeout of 8s max
//   3. Always resolves — never hangs indefinitely




// ── App ───────────────────────────────────────────────────────────────────────

class MsalPlusApp extends ConsumerWidget {
  const MsalPlusApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(appThemeProvider);

    return MaterialApp(
      title: 'MSAL+',
      debugShowCheckedModeBanner: false,
      theme: themeState.themeData,
      darkTheme: themeState.themeData,
      themeMode: themeState.themeMode,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ru', 'RU'),
        Locale('en', 'US'),
      ],
      builder: (context, child) {
        // Clamp text scale to prevent overflow on devices with large font settings
        final mediaQuery = MediaQuery.of(context);
        final clampedScale = mediaQuery.textScaler.clamp(
          minScaleFactor: 0.8,
          maxScaleFactor: 1.15,
        );
        return MediaQuery(
          data: mediaQuery.copyWith(textScaler: clampedScale),
          child: child!,
        );
      },
      home: ref.watch(sessionProvider).when(
        loading: () => const _SplashScreen(),
        error: (_, __) => const LoginScreen(),
        data: (isAuth) => isAuth ? const MainShell() : const LoginScreen(),
      ),
    );
  }
}

// ── Splash ────────────────────────────────────────────────────────────────────

class _SplashScreen extends ConsumerWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: AppTheme.accentGradient,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accent.withOpacity(0.4),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Text(
                'М+',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 24),
            ShaderMask(
              shaderCallback: (r) => AppTheme.accentGradient.createShader(r),
              child: const Text(
                'MSAL+',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Личный кабинет МГЮА',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.accent.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
