import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass_tokens.dart';
import 'package:intheloopapp/ui/design/tapped_theme_extension.dart';

export 'package:intheloopapp/ui/design/tapped_theme_extension.dart'
    show TappedThemeContext;

const Color tappedAccent = TappedColors.accent;

const Color backgroundLightColor = TappedColors.backgroundLight;
const Color backgroundDarkColor = TappedColors.backgroundDark;
const Color navigationBarLightColor = TappedColors.backgroundLight;
const Color navigationBarDarkColor = TappedColors.backgroundDark;

ThemeData buildLightTheme({
  Color accentColor = tappedAccent,
}) =>
    buildTheme(brightness: Brightness.light, accentColor: accentColor);

ThemeData buildDarkTheme({
  Color accentColor = tappedAccent,
}) =>
    buildTheme(brightness: Brightness.dark, accentColor: accentColor);

/// Maps the [TappedTypography] ramp onto Material's `TextTheme` slots so
/// `theme.textTheme.*` is the single typography source for views.
///
/// Uses the platform system font (SF Pro on iOS, Roboto on Android) with
/// Apple's tight display tracking, so the app reads like a native iOS app.
TextTheme buildTextTheme(Brightness brightness) {
  final base = brightness == Brightness.dark
      ? ThemeData.dark().textTheme
      : ThemeData.light().textTheme;

  final ramp = base.copyWith(
    displayLarge: base.displayLarge?.merge(TappedTypography.displayLg),
    displayMedium: base.displayMedium?.merge(TappedTypography.displayMd),
    headlineLarge: base.headlineLarge?.merge(TappedTypography.headingLg),
    headlineMedium: base.headlineMedium?.merge(TappedTypography.headingMd),
    headlineSmall: base.headlineSmall?.merge(TappedTypography.headingSm),
    titleLarge: base.titleLarge?.merge(TappedTypography.headingMd),
    titleMedium: base.titleMedium?.merge(TappedTypography.headingSm),
    titleSmall: base.titleSmall?.merge(TappedTypography.headingXs),
    bodyLarge: base.bodyLarge?.merge(TappedTypography.bodyLg),
    bodyMedium: base.bodyMedium?.merge(TappedTypography.bodyMd),
    bodySmall: base.bodySmall?.merge(TappedTypography.bodySm),
    labelLarge: base.labelLarge?.merge(TappedTypography.bodyMd),
    labelMedium: base.labelMedium?.merge(TappedTypography.label),
    labelSmall: base.labelSmall?.merge(TappedTypography.caption),
  );

  return ramp.copyWith(
    displayLarge: ramp.displayLarge?.copyWith(letterSpacing: -0.8),
    displayMedium: ramp.displayMedium?.copyWith(letterSpacing: -0.6),
    headlineLarge: ramp.headlineLarge?.copyWith(letterSpacing: -0.5),
    headlineMedium: ramp.headlineMedium?.copyWith(letterSpacing: -0.4),
    titleLarge: ramp.titleLarge?.copyWith(letterSpacing: -0.4),
    titleMedium: ramp.titleMedium?.copyWith(letterSpacing: -0.2),
  );
}

ThemeData buildTheme({
  required Brightness brightness,
  Color accentColor = tappedAccent,
}) {
  final isDark = brightness == Brightness.dark;
  final primaryColor = accentColor;

  final background = isDark ? backgroundDarkColor : backgroundLightColor;
  final surface = isDark ? TappedColors.surfaceDark : TappedColors.surfaceLight;
  final onBackground = isDark ? Colors.white : Colors.black;
  final tokens =
      isDark ? TappedThemeExtension.dark() : TappedThemeExtension.light();

  final baseScheme =
      isDark ? const ColorScheme.dark() : const ColorScheme.light();
  final colorScheme = baseScheme.copyWith(
    primary: primaryColor,
    onPrimary: Colors.white,
    secondary: primaryColor,
    onSecondary: Colors.white,
    surface: background,
    onSurface: onBackground,
    surfaceContainer: surface,
    surfaceContainerHighest: surface,
    error: TappedColors.error,
    outline: tokens.divider,
    outlineVariant: tokens.divider,
  );

  final textTheme = buildTextTheme(brightness);
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
  );

  return base.copyWith(
    textTheme: textTheme,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    splashColor: Colors.transparent,
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final platform in TargetPlatform.values)
          platform: const CupertinoPageTransitionsBuilder(),
      },
    ),
    primaryColor: primaryColor,
    scaffoldBackgroundColor: background,
    canvasColor: background,
    cardColor: surface,
    dividerColor: tokens.divider,
    extensions: <ThemeExtension<dynamic>>[tokens],

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primaryColor,
      foregroundColor: colorScheme.onPrimary,
    ),

    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: background,
      selectedItemColor: primaryColor,
      unselectedItemColor: tokens.mutedText,
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: background,
      indicatorColor: primaryColor.withValues(alpha: 0.15),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? primaryColor
              : tokens.mutedText,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => textTheme.labelMedium?.copyWith(
          color: states.contains(WidgetState.selected)
              ? primaryColor
              : tokens.mutedText,
        ),
      ),
    ),

    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: onBackground,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: textTheme.titleMedium?.copyWith(
        color: onBackground,
        fontWeight: FontWeight.w600,
      ),
    ),

    tabBarTheme: TabBarThemeData(
      indicatorColor: primaryColor,
      labelColor: onBackground,
      unselectedLabelColor: tokens.mutedText,
      labelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      unselectedLabelStyle: textTheme.labelLarge,
      dividerColor: Colors.transparent,
    ),

    sliderTheme: SliderThemeData(
      activeTrackColor: primaryColor,
      inactiveTrackColor: primaryColor.withValues(alpha: 0.24),
      thumbColor: primaryColor,
      overlayColor: primaryColor.withValues(alpha: 0.12),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
      trackHeight: 3,
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colorScheme.onPrimary
            : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? primaryColor : null,
      ),
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: primaryColor,
    ),

    iconTheme: IconThemeData(color: onBackground),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size.square(TappedSizes.minTapTarget),
        foregroundColor: onBackground,
      ),
    ),

    cupertinoOverrideTheme: CupertinoThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: background,
      barBackgroundColor: background,
      primaryColor: primaryColor,
      textTheme: CupertinoTextThemeData(
        primaryColor: primaryColor,
        textStyle: textTheme.bodyLarge?.copyWith(color: onBackground),
      ),
    ),

    // ── Component themes ──────────────────────────────────────────────

    cardTheme: CardThemeData(
      elevation: 0,
      color: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: TappedRadius.lgAll),
      margin: const EdgeInsets.symmetric(
        horizontal: TappedSpacing.lg,
        vertical: TappedSpacing.sm,
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: onBackground.withValues(alpha: isDark ? 0.10 : 0.05),
      hintStyle: textTheme.bodyLarge?.copyWith(color: tokens.mutedText),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: TappedSpacing.lg,
        vertical: TappedSpacing.md,
      ),
      border: OutlineInputBorder(
        borderRadius: GlassRadius.controlAll,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: GlassRadius.controlAll,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: GlassRadius.controlAll,
        borderSide: BorderSide(color: primaryColor, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: GlassRadius.controlAll,
        borderSide: const BorderSide(color: TappedColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: GlassRadius.controlAll,
        borderSide: const BorderSide(color: TappedColors.error, width: 1.5),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: colorScheme.onPrimary,
        disabledBackgroundColor: primaryColor.withValues(alpha: 0.38),
        disabledForegroundColor: colorScheme.onPrimary.withValues(alpha: 0.7),
        minimumSize:
            const Size(TappedSizes.minTapTarget, TappedSizes.minTapTarget),
        shape: const StadiumBorder(),
        textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(
          horizontal: TappedSpacing.xl,
          vertical: TappedSpacing.md,
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryColor,
        side: BorderSide(color: primaryColor),
        minimumSize:
            const Size(TappedSizes.minTapTarget, TappedSizes.minTapTarget),
        shape: const StadiumBorder(),
        textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(
          horizontal: TappedSpacing.xl,
          vertical: TappedSpacing.md,
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryColor,
        minimumSize:
            const Size(TappedSizes.minTapTarget, TappedSizes.minTapTarget),
        shape: const StadiumBorder(),
        textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(
          horizontal: TappedSpacing.lg,
          vertical: TappedSpacing.sm,
        ),
      ),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: surface,
      selectedColor: primaryColor.withValues(alpha: isDark ? 0.25 : 0.15),
      labelStyle: textTheme.labelMedium?.copyWith(color: onBackground),
      shape: const StadiumBorder(),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(
        horizontal: TappedSpacing.sm,
        vertical: TappedSpacing.xs,
      ),
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: tokens.mutedText,
      shape: RoundedRectangleBorder(borderRadius: GlassRadius.sheetTop),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: GlassRadius.cardAll),
    ),

    listTileTheme: ListTileThemeData(
      iconColor: onBackground,
      textColor: onBackground,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: TappedSpacing.lg,
      ),
      shape: RoundedRectangleBorder(borderRadius: GlassRadius.controlAll),
    ),

    dividerTheme: DividerThemeData(
      color: tokens.divider,
      thickness: 1,
      space: 1,
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? TappedColors.surfaceDark : Colors.black87,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
      shape: const StadiumBorder(),
    ),
  );
}

extension ThemeUtil on BuildContext {
  ThemeData get theme => Theme.of(this);
}
