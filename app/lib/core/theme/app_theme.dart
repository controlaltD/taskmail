import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// TaskMail brand palette — fiatalos, élénk, ServeOS-tól független identitás.
/// A kanban kártya szemantikus színei (priority/label) tudatosan közel állnak
/// a ServeOS FeladatokBoard színeihez, hogy egy szinkronizált kártya ne
/// hasson idegennek egyik rendszerben sem.
class AppColors {
  AppColors._();

  static const primary = Color(0xFF6C5CE7); // indigo/purple
  static const primaryDark = Color(0xFF4834D4);
  static const accent = Color(0xFFFF6B9D); // coral/pink
  static const accentSecondary = Color(0xFFFFB84D); // warm orange

  static const bgLight = Color(0xFFFAFAFE);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceLight2 = Color(0xFFF2F1FA);

  static const bgDark = Color(0xFF141220);
  static const surfaceDark = Color(0xFF1E1B2E);
  static const surfaceDark2 = Color(0xFF29253D);

  // Priority — ServeOS `task_priority` enummal összhangban
  static const priorityUrgent = Color(0xFFFF6B81);
  static const priorityHigh = Color(0xFFF97316);
  static const priorityMedium = Color(0xFF6C5CE7);
  static const priorityLow = Color(0xFF2ED573);

  // Label — ServeOS LABEL_OPTIONS-szal összhangban
  static const labelUrgent = Color(0xFFFF6B81);
  static const labelOps = Color(0xFF60A5FA);
  static const labelKitchen = Color(0xFFF97316);
  static const labelService = Color(0xFFA78BFA);
  static const labelAdmin = Color(0xFF34D399);
  static const labelEvent = Color(0xFF6C5CE7);
}

class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgDark : AppColors.bgLight;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.accent,
      onSecondary: Colors.white,
      error: AppColors.priorityUrgent,
      onError: Colors.white,
      surface: surface,
      onSurface: isDark ? const Color(0xFFEDEBF7) : const Color(0xFF1E1B2E),
    );

    final headlineFont = GoogleFonts.baloo2TextTheme();
    final bodyFont = GoogleFonts.interTextTheme();

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bg,
      textTheme: bodyFont.copyWith(
        headlineLarge: headlineFont.headlineLarge?.copyWith(fontWeight: FontWeight.w700),
        headlineMedium: headlineFont.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
        headlineSmall: headlineFont.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
        titleLarge: headlineFont.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: headlineFont.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: colorScheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.surfaceDark2 : AppColors.surfaceLight2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? AppColors.surfaceDark2 : AppColors.surfaceLight2,
        labelStyle: TextStyle(color: colorScheme.onSurface, fontSize: 11, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}
