import 'package:flutter/material.dart';

class AppTheme {
  static const Color bgSurface = Color(0xFFF7F6F2);
  static const Color cardWhite = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF1F2329);
  static const Color textSecondary = Color(0xFF6E737D);
  static const Color accentCharcoal = Color(0xFF2B2D33);
  static const Color heartRed = Color(0xFFE85A5A);
  static const Color tagBg = Color(0xFFF1F2F4);
  static const Color dividerColor = Color(0xFFEBEAE4);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: bgSurface,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accentCharcoal,
        surface: bgSurface,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bgSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      cardTheme: CardThemeData(
        color: cardWhite,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: dividerColor, width: 1),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: tagBg,
        labelStyle: const TextStyle(fontSize: 11, color: textSecondary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide.none,
      ),
    );
  }
}
