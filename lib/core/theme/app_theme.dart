import 'package:flutter/material.dart';

abstract final class YenkoColors {
  static const gold = Color(0xFFE5A900);
  static const charcoal = Color(0xFF202124);
  static const cream = Color(0xFFF8F7F3);
  static const gray = Color(0xFF6B7280);
  static const green = Color(0xFF238636);
  static const red = Color(0xFFE5484D);
}

abstract final class YenkoTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: YenkoColors.gold,
      brightness: Brightness.light,
      primary: YenkoColors.gold,
      onPrimary: YenkoColors.charcoal,
      surface: Colors.white,
      onSurface: YenkoColors.charcoal,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: YenkoColors.cream,
      appBarTheme: const AppBarTheme(
        backgroundColor: YenkoColors.cream,
        foregroundColor: YenkoColors.charcoal,
        elevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE1E4E8)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE1E4E8)),
        ),
      ),
    );
  }
}
