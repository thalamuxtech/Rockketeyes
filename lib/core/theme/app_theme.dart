import 'dart:ui';

import 'package:flutter/material.dart';

/// Design tokens for the "Cosmic Glass" look.
abstract final class AppColors {
  static const bgDeep = Color(0xFF07060F);
  static const bgIndigo = Color(0xFF141026);
  static const board = Color(0xFF15131F);
  static const boardEdge = Color(0xFF221E33);
  static const gold = Color(0xFFF5B83D);
  static const goldDeep = Color(0xFFD9951E);
  static const goldSoft = Color(0xFFFFE3A3);
  static const violet = Color(0xFF7C5CFF);
  static const text = Color(0xFFF4F2FF);
  static const textMuted = Color(0xFFA9A5C4);
  static const textFaint = Color(0xFF6F6A8C);
  static const success = Color(0xFF2EE59D);
  static const error = Color(0xFFFF4D5E);
  static const glassFill = Color(0x14FFFFFF);
  static const glassFillStrong = Color(0x1FFFFFFF);
  static const glassBorder = Color(0x24FFFFFF);
  static const silver = Color(0xFFD7DCE6);
  static const bronze = Color(0xFFE0915A);

  static const goldGradient = LinearGradient(
    colors: [goldSoft, gold, goldDeep],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

abstract final class AppSpace {
  static const xs = 4.0, sm = 8.0, md = 12.0, lg = 16.0, xl = 24.0, xxl = 32.0, xxxl = 48.0;
}

abstract final class AppRadius {
  static const sm = 12.0, md = 20.0, lg = 28.0;
}

abstract final class AppMotion {
  static const micro = Duration(milliseconds: 180);
  static const short = Duration(milliseconds: 280);
  static const medium = Duration(milliseconds: 420);
  static const curve = Curves.easeOutCubic;
}

/// Text styles. Both fonts are variable, so weight is also applied as a
/// `wght` axis variation.
abstract final class AppText {
  static TextStyle _style(String family, double size, FontWeight weight,
      {double? height, double spacing = 0, Color color = AppColors.text}) {
    return TextStyle(
      fontFamily: family,
      fontSize: size,
      fontWeight: weight,
      fontVariations: [FontVariation.weight(weight.value.toDouble())],
      height: height,
      letterSpacing: spacing,
      color: color,
    );
  }

  static TextStyle display(double size, {FontWeight weight = FontWeight.w800, Color color = AppColors.text}) =>
      _style('Sora', size, weight, height: 1.05, spacing: -0.5, color: color);

  static TextStyle heading(double size, {FontWeight weight = FontWeight.w700, Color color = AppColors.text}) =>
      _style('Sora', size, weight, height: 1.2, spacing: -0.2, color: color);

  static TextStyle body(double size, {FontWeight weight = FontWeight.w400, Color color = AppColors.text}) =>
      _style('Inter', size, weight, height: 1.5, color: color);

  static TextStyle label(double size, {FontWeight weight = FontWeight.w600, Color color = AppColors.text}) =>
      _style('Inter', size, weight, height: 1.2, spacing: 0.2, color: color);

  /// Numbers that change (timer, score): tabular so digits don't jitter.
  static TextStyle numeric(double size, {FontWeight weight = FontWeight.w700, Color color = AppColors.text}) =>
      _style('Inter', size, weight, height: 1.1, color: color)
          .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  static TextStyle boardWord(double size, Color color) =>
      _style('Sora', size, FontWeight.w700, height: 1.0, spacing: 0, color: color);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.gold,
    brightness: Brightness.dark,
  ).copyWith(
    primary: AppColors.gold,
    onPrimary: const Color(0xFF1A1206),
    secondary: AppColors.violet,
    surface: AppColors.bgIndigo,
    onSurface: AppColors.text,
    error: AppColors.error,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bgDeep,
    fontFamily: 'Inter',
    splashFactory: InkSparkle.splashFactory,
  );

  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      displayLarge: AppText.display(48),
      displayMedium: AppText.display(36),
      headlineMedium: AppText.heading(26),
      titleLarge: AppText.heading(20),
      titleMedium: AppText.label(16),
      bodyLarge: AppText.body(16),
      bodyMedium: AppText.body(14),
      labelLarge: AppText.label(15),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.gold,
      inactiveTrackColor: AppColors.glassFillStrong,
      thumbColor: AppColors.gold,
      overlayColor: Color(0x33F5B83D),
      trackHeight: 4,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.bgDeep : AppColors.textMuted),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.gold : AppColors.glassFillStrong),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.bgIndigo,
      contentTextStyle: AppText.body(14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        side: const BorderSide(color: AppColors.glassBorder),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.glassFill,
      hintStyle: AppText.body(15, color: AppColors.textFaint),
      labelStyle: AppText.label(14, color: AppColors.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: AppColors.glassBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: AppColors.glassBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: AppColors.gold, width: 1.5),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.bgIndigo,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: AppColors.glassBorder),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}
