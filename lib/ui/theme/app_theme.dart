import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// Builds the app-wide Material 3 dark theme from the brand seed color.
ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.seed,
    brightness: Brightness.dark,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    visualDensity: VisualDensity.standard,
    textTheme: _textTheme(scheme),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.teal700.withValues(alpha: 0.35),
      height: 80,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      margin: EdgeInsets.zero,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(AppMetrics.bigButtonHeight),
        textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(56, 56),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.textSubdued),
        ),
      ),
    ),
  );
}

TextTheme _textTheme(ColorScheme scheme) {
  return TextTheme(
    displayLarge: const TextStyle(
      fontSize: 40,
      height: 1.15,
      fontWeight: FontWeight.w800,
      color: AppColors.textPrimary,
    ),
    headlineMedium: const TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
    ),
    titleLarge: const TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
    ),
    bodyLarge: const TextStyle(
      fontSize: 18,
      height: 1.4,
      color: AppColors.textPrimary,
    ),
    bodyMedium: const TextStyle(
      fontSize: 16,
      height: 1.4,
      color: AppColors.textSubdued,
    ),
    labelLarge: const TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
    ),
  );
}