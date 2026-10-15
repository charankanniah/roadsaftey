import 'package:flutter/material.dart';

class AppTheme {
  // Brand & Safety Palette
  static const Color primaryDark = Color(0xFF0F172A); // Slate 900
  static const Color surfaceDark = Color(0xFF1E293B); // Slate 800
  static const Color cardDark = Color(0xFF334155); // Slate 700
  static const Color accentCyan = Color(0xFF06B6D4); // Cyan 500

  // Severity Danger Spectrum
  static const Color severityLow = Color(0xFF22C55E); // Green (Level 1-2)
  static const Color severityMedium = Color(0xFFF59E0B); // Amber (Level 3)
  static const Color severityHigh = Color(0xFFEF4444); // Red (Level 4-5)
  static const Color severityCritical = Color(0xFFDC2626); // Crimson Red

  // High-Contrast Drive Mode Themes
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0B0F17),
      primaryColor: accentCyan,
      colorScheme: const ColorScheme.dark(
        primary: accentCyan,
        secondary: Color(0xFF38BDF8),
        surface: surfaceDark,
        error: severityHigh,
      ),
      cardTheme: CardTheme(
        color: surfaceDark,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 28),
        titleLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20),
        bodyLarge: TextStyle(color: Color(0xFFE2E8F0), fontSize: 16),
        bodyMedium: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0B0F17),
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
      ),
    );
  }

  // Returns severity color matching level 1-5
  static Color getSeverityColor(int severity) {
    if (severity <= 2) return severityLow;
    if (severity == 3) return severityMedium;
    return severityHigh;
  }
}
