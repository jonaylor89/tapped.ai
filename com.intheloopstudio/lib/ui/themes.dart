import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';

// const itlAccent = Color(0xff6200ee);
const tappedAccent = Color(0xff0086CC);

// const primaryColor = Colors.deepPurple;
// const secondaryColor = Colors.deepPurple;
const backgroundLightColor = Color(0xfff8f6Fb);
const backgroundDarkColor = Color(0xff010F16);
const navigationBarLightColor = Color(0xfff8f6Fb);
const navigationBarDarkColor = Color(0xff010F16);

ThemeData buildLightTheme({
  Color accentColor = tappedAccent,
}) {
  final primaryColor = accentColor;
  final secondaryColor = accentColor;

  return ThemeData.light().copyWith(
    textTheme: GoogleFonts.titilliumWebTextTheme(
      ThemeData.light().textTheme,
    ),

    // selected color
    primaryColor: primaryColor,

    colorScheme: const ColorScheme.light().copyWith(
      primary: primaryColor,
      secondary: secondaryColor,
      surface: backgroundLightColor,
      error: TappedColors.error,
    ),

    // floating action button
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
    ),

    // bottom bar
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: navigationBarLightColor,
      selectedItemColor: primaryColor,
      unselectedItemColor: Colors.black,
    ),
    // switch active color
    canvasColor: backgroundLightColor,
    appBarTheme: const AppBarTheme(
      backgroundColor: backgroundLightColor,
      foregroundColor: Colors.black,
    ),

    tabBarTheme: const TabBarThemeData(
      labelColor: Colors.black,
      unselectedLabelColor: Colors.black,
      indicatorColor: tappedAccent,
    ),

    sliderTheme: const SliderThemeData(
      activeTrackColor: tappedAccent,
      inactiveTrackColor: tappedAccent,
      thumbColor: tappedAccent,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
      trackHeight: 2,
    ),

    cupertinoOverrideTheme: const CupertinoThemeData(
      scaffoldBackgroundColor: backgroundLightColor,
      primaryColor: tappedAccent,
      textTheme: CupertinoTextThemeData(
        textStyle: TextStyle(
          fontFamily: 'TitilliumWeb',
        ),
      ),
    ),

    // ── Component themes ──────────────────────────────────────────────

    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: TappedRadius.lgAll),
      color: Colors.white,
      margin: const EdgeInsets.symmetric(
        horizontal: TappedSpacing.lg,
        vertical: TappedSpacing.sm,
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.grey.shade100,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: TappedSpacing.lg,
        vertical: TappedSpacing.md,
      ),
      border: OutlineInputBorder(
        borderRadius: TappedRadius.mdAll,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: TappedRadius.mdAll,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: TappedRadius.mdAll,
        borderSide: const BorderSide(color: tappedAccent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: TappedRadius.mdAll,
        borderSide: const BorderSide(color: TappedColors.error),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: TappedRadius.lgAll),
        padding: const EdgeInsets.symmetric(
          horizontal: TappedSpacing.xl,
          vertical: TappedSpacing.md,
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryColor,
        shape: RoundedRectangleBorder(borderRadius: TappedRadius.lgAll),
        padding: const EdgeInsets.symmetric(
          horizontal: TappedSpacing.lg,
          vertical: TappedSpacing.sm,
        ),
      ),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: Colors.grey.shade100,
      selectedColor: primaryColor.withValues(alpha: 0.15),
      labelStyle: const TextStyle(fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: TappedRadius.smAll),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(
        horizontal: TappedSpacing.sm,
        vertical: TappedSpacing.xs,
      ),
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(TappedRadius.xl),
        ),
      ),
    ),

    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: TappedRadius.xlAll),
    ),

    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: TappedSpacing.lg,
      ),
      shape: RoundedRectangleBorder(borderRadius: TappedRadius.mdAll),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: TappedRadius.mdAll),
    ),
  );
}

ThemeData buildDarkTheme({
  Color accentColor = tappedAccent,
}) {
  final primaryColor = accentColor;
  final secondaryColor = accentColor;

  return ThemeData.dark().copyWith(
    textTheme: GoogleFonts.titilliumWebTextTheme(
      ThemeData.dark().textTheme,
    ),

    // selected color
    primaryColor: primaryColor,
    colorScheme: const ColorScheme.dark().copyWith(
      primary: primaryColor,
      secondary: secondaryColor,
      surface: backgroundDarkColor,
      error: TappedColors.error,
    ),
    // floating action button
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
    ),
    // bottom bar
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: navigationBarDarkColor,
      selectedItemColor: primaryColor,
      unselectedItemColor: const Color(0xFF757575),
    ),
    // switch active color
    canvasColor: backgroundDarkColor,
    appBarTheme: const AppBarTheme(
      backgroundColor: navigationBarDarkColor,
    ),

    tabBarTheme: const TabBarThemeData(
      indicatorColor: tappedAccent,
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white,
    ),

    sliderTheme: const SliderThemeData(
      activeTrackColor: tappedAccent,
      inactiveTrackColor: tappedAccent,
      thumbColor: tappedAccent,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
      trackHeight: 2,
    ),

    cupertinoOverrideTheme: const CupertinoThemeData(
      scaffoldBackgroundColor: backgroundDarkColor,
      primaryColor: tappedAccent,
      textTheme: CupertinoTextThemeData(
        textStyle: TextStyle(
          fontFamily: 'TitilliumWeb',
        ),
      ),
    ),

    // ── Component themes ──────────────────────────────────────────────

    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: TappedRadius.lgAll),
      color: const Color(0xff1C2B33),
      margin: const EdgeInsets.symmetric(
        horizontal: TappedSpacing.lg,
        vertical: TappedSpacing.sm,
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xff1C2B33),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: TappedSpacing.lg,
        vertical: TappedSpacing.md,
      ),
      border: OutlineInputBorder(
        borderRadius: TappedRadius.mdAll,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: TappedRadius.mdAll,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: TappedRadius.mdAll,
        borderSide: const BorderSide(color: tappedAccent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: TappedRadius.mdAll,
        borderSide: const BorderSide(color: TappedColors.error),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: TappedRadius.lgAll),
        padding: const EdgeInsets.symmetric(
          horizontal: TappedSpacing.xl,
          vertical: TappedSpacing.md,
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryColor,
        shape: RoundedRectangleBorder(borderRadius: TappedRadius.lgAll),
        padding: const EdgeInsets.symmetric(
          horizontal: TappedSpacing.lg,
          vertical: TappedSpacing.sm,
        ),
      ),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: const Color(0xff1C2B33),
      selectedColor: primaryColor.withValues(alpha: 0.25),
      labelStyle: const TextStyle(fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: TappedRadius.smAll),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(
        horizontal: TappedSpacing.sm,
        vertical: TappedSpacing.xs,
      ),
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(TappedRadius.xl),
        ),
      ),
    ),

    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: TappedRadius.xlAll),
    ),

    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: TappedSpacing.lg,
      ),
      shape: RoundedRectangleBorder(borderRadius: TappedRadius.mdAll),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: TappedRadius.mdAll),
    ),
  );
}

extension ThemeUtil on BuildContext {
  ThemeData get theme => Theme.of(this);
}
