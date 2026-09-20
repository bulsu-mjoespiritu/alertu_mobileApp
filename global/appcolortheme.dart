import 'package:flutter/material.dart';

class AppColorTheme {
  // Brand Color Constants
  static const Color primaryBlue = Color(0xFF0D47A1);

  // ☀️ LIGHT THEME CONFIGURATION
  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primaryColor: primaryBlue,
    scaffoldBackgroundColor: const Color(0xFFFBFBFB), // Matches your flat canvas deck

    // AppBar Theme config
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: primaryBlue,
      elevation: 1,
    ),

    // Bottom Navigation Customization Blueprint
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xFFFBFBFB),
      selectedItemColor: primaryBlue,
      unselectedItemColor: Colors.grey,
    ),
  );

  // 🌙 DARK THEME CONFIGURATION
  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    primaryColor: primaryBlue,
    scaffoldBackgroundColor: const Color(0xFF121212), // Premium deep dark canvas surface

    // AppBar Theme config
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1E1E1E),
      foregroundColor: Colors.white,
      elevation: 1,
    ),

    // Bottom Navigation Customization Blueprint
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xFF1E1E1E),
      selectedItemColor: Colors.white,
      unselectedItemColor: Colors.grey,
    ),
  );
}