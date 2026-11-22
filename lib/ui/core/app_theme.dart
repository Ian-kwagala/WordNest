import 'package:flutter/material.dart';

/// "Calm Morning Coffee Shop" visual palette and styling from the WordNest blueprint.
class WordNestTheme {
  WordNestTheme._();

  static const Color paperBackground = Color(0xFFF7F9F6);
  static const Color gridCard = Color(0xFFFFFFFF);
  static const Color letterSlate = Color(0xFF1F2937);
  static const Color subtleSlate = Color(0xFF6B7280);
  static const Color borderSoft = Color(0xFFE5E7EB);
  static const Color coffeeAccent = Color(0xFF134E4A); // Deep pine/coffee teal
  static const Color warmCream = Color(0xFFFEF9C3);

  /// Five pastel highlighter colors drawn semi-transparently under letters.
  static const List<Color> highlighterColors = [
    Color(0xFFFDE047), // Sun
    Color(0xFF6EE7B7), // Mint
    Color(0xFF7DD3FC), // Sky
    Color(0xFFFDA4AF), // Rose
    Color(0xFFC4B5FD), // Lavender
  ];

  static Color parseHex(String hex, {Color fallback = const Color(0xFF6EE7B7)}) {
    final cleaned = hex.replaceAll('#', '').trim();
    if (cleaned.length == 6) {
      final value = int.tryParse('FF$cleaned', radix: 16);
      if (value != null) return Color(value);
    }
    return fallback;
  }

  static ThemeData buildThemeData() {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: paperBackground,
      colorScheme: ColorScheme.fromSeed(
        seedColor: coffeeAccent,
        surface: gridCard,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: paperBackground,
        foregroundColor: letterSlate,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: gridCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: borderSoft),
        ),
      ),
    );
  }
}
