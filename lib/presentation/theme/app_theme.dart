import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Couleurs principales
  static const Color primaryColor = Color(0xFF2196F3); // Bleu principal
  static const Color primaryLightColor = Color(0xFF64B5F6);
  static const Color primaryDarkColor = Color(0xFF1976D2);
  static const Color accentColor = Color(0xFF4CAF50);
  static const Color backgroundColor = Color(0xFF121212);

  // Couleurs pour les graphiques
  static const Color chartLine1 = Color(0xFF4CAF50); // Vert pour l'énergie
  static const Color chartLine2 = Color(0xFFFFC107); // NOUVEAU : Jaune (ou AppTheme.chartLine1 si vous préférez vert)
  static const Color chartLine3 = Color(0xFF4CAF50); // NOUVEAU : Vert (si chartLine2 est jaune)
  static const Color chartLine4 = Color(0xFFFF9800); // Orange secondaire

  // Couleurs pour les cartes
  static const Color cardColor = Color(0xFF1E1E1E);
  static const Color cardBorderColor = Color(0xFF424242);

  // Couleurs pour le texte
  static const Color textPrimaryColor = Color(0xFFFFFFFF);
  static const Color textSecondaryColor = Color(0xFFB0B0B0);
  static const Color textAccentColor = Color(0xFFE0E0E0);

  // Opacités pour l'effet glassmorphism
  static const double glassMorphismOpacity = 0.1;
  static const double glassMorphismBlur = 10.0;

  // Arrondis
  static const double borderRadius = 16.0;
  static const double borderRadiusSmall = 8.0;
  static const double borderRadiusLarge = 24.0;

  // Ombre standard
  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color(0x40000000),
      blurRadius: 15,
      offset: Offset(0, 4),
    ),
  ];

  static ThemeData getTheme() {
    return ThemeData(
      primaryColor: primaryColor,
      primaryColorDark: primaryDarkColor,
      primaryColorLight: primaryLightColor,
      scaffoldBackgroundColor: backgroundColor,
      canvasColor: backgroundColor,
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: accentColor,
        surface: cardColor,
      ),
      useMaterial3: true,
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: backgroundColor.withOpacity(0.8),
        indicatorColor: primaryColor.withOpacity(0.2),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w500,
            fontSize: 12,
          ),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: textPrimaryColor,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          fontSize: 18,
          color: textPrimaryColor,
        ),
      ),
      textTheme: GoogleFonts.poppinsTextTheme(
        const TextTheme(
          displayLarge: TextStyle(color: textPrimaryColor),
          displayMedium: TextStyle(color: textPrimaryColor),
          displaySmall: TextStyle(color: textPrimaryColor),
          headlineLarge: TextStyle(color: textPrimaryColor),
          headlineMedium: TextStyle(color: textPrimaryColor),
          headlineSmall: TextStyle(color: textPrimaryColor),
          titleLarge:
              TextStyle(color: textPrimaryColor, fontWeight: FontWeight.w600),
          titleMedium:
              TextStyle(color: textPrimaryColor, fontWeight: FontWeight.w600),
          titleSmall:
              TextStyle(color: textPrimaryColor, fontWeight: FontWeight.w500),
          bodyLarge: TextStyle(color: textPrimaryColor),
          bodyMedium: TextStyle(color: textSecondaryColor),
          bodySmall: TextStyle(color: textSecondaryColor),
          labelLarge:
              TextStyle(color: textPrimaryColor, fontWeight: FontWeight.w500),
          labelMedium: TextStyle(color: textSecondaryColor),
          labelSmall: TextStyle(color: textSecondaryColor),
        ),
      ),
      cardTheme: CardTheme(
        color: cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          side: const BorderSide(color: cardBorderColor, width: 0.5),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: cardBorderColor,
        thickness: 0.5,
      ),
      buttonTheme: ButtonThemeData(
        buttonColor: primaryColor,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadiusSmall),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: textPrimaryColor,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadiusSmall),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: const BorderSide(color: primaryColor),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadiusSmall),
          ),
        ),
      ),
      iconTheme: const IconThemeData(
        color: textPrimaryColor,
        size: 24,
      ),
      inputDecorationTheme: InputDecorationTheme(
        fillColor: cardColor,
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadiusSmall),
          borderSide: const BorderSide(color: cardBorderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadiusSmall),
          borderSide: const BorderSide(color: cardBorderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadiusSmall),
          borderSide: const BorderSide(color: primaryColor),
        ),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        hintStyle: const TextStyle(color: textSecondaryColor),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: cardColor,
        disabledColor: cardColor.withOpacity(0.5),
        selectedColor: primaryColor,
        secondarySelectedColor: primaryColor,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        labelStyle: const TextStyle(color: textPrimaryColor),
        secondaryLabelStyle: const TextStyle(color: textPrimaryColor),
        brightness: Brightness.dark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadiusSmall),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: cardColor,
        selectedItemColor: primaryColor,
        unselectedItemColor: textSecondaryColor,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        elevation: 8,
      ),
    );
  }

  // Widget pour créer un effet glassmorphism
  static Widget createGlassMorphism({
    required Widget child,
    double opacity = glassMorphismOpacity,
    double blur = glassMorphismBlur,
    Color color = cardColor,
    double borderRadius = AppTheme.borderRadius,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(
            color: color.withOpacity(opacity),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
              width: 0.5,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
