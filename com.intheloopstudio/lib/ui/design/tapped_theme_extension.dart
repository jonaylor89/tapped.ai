import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';

/// Brightness-aware semantic colors that `ColorScheme` doesn't cover.
///
/// Read via `context.tokens` (see [TappedThemeContext]).
@immutable
class TappedThemeExtension extends ThemeExtension<TappedThemeExtension> {
  const TappedThemeExtension({
    required this.success,
    required this.onSuccess,
    required this.warning,
    required this.onWarning,
    required this.info,
    required this.onInfo,
    required this.mutedText,
    required this.divider,
    required this.elevatedSurface,
    required this.textOnImage,
    required this.textOnImageMuted,
    required this.scrim,
    required this.scrimLight,
  });

  factory TappedThemeExtension.light() => const TappedThemeExtension(
        success: TappedColors.success,
        onSuccess: Colors.white,
        warning: TappedColors.warning,
        onWarning: Colors.black,
        info: TappedColors.accent,
        onInfo: Colors.white,
        mutedText: Color(0x99000000),
        divider: Color(0x33000000),
        elevatedSurface: Colors.white,
        textOnImage: TappedColors.textOnImage,
        textOnImageMuted: TappedColors.textOnImageMuted,
        scrim: TappedColors.scrim,
        scrimLight: TappedColors.scrimLight,
      );

  factory TappedThemeExtension.dark() => const TappedThemeExtension(
        success: TappedColors.success,
        onSuccess: Colors.black,
        warning: TappedColors.warning,
        onWarning: Colors.black,
        info: TappedColors.accent,
        onInfo: Colors.white,
        mutedText: Color(0x99FFFFFF),
        divider: Color(0x33FFFFFF),
        elevatedSurface: TappedColors.surfaceDark,
        textOnImage: TappedColors.textOnImage,
        textOnImageMuted: TappedColors.textOnImageMuted,
        scrim: TappedColors.scrim,
        scrimLight: TappedColors.scrimLight,
      );

  final Color success;
  final Color onSuccess;
  final Color warning;
  final Color onWarning;
  final Color info;
  final Color onInfo;

  /// Secondary text (captions, hints, timestamps).
  final Color mutedText;

  /// Hairline separators.
  final Color divider;

  /// Cards, inputs and chips sitting on top of the scaffold background.
  final Color elevatedSurface;

  final Color textOnImage;
  final Color textOnImageMuted;
  final Color scrim;
  final Color scrimLight;

  @override
  TappedThemeExtension copyWith({
    Color? success,
    Color? onSuccess,
    Color? warning,
    Color? onWarning,
    Color? info,
    Color? onInfo,
    Color? mutedText,
    Color? divider,
    Color? elevatedSurface,
    Color? textOnImage,
    Color? textOnImageMuted,
    Color? scrim,
    Color? scrimLight,
  }) {
    return TappedThemeExtension(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      mutedText: mutedText ?? this.mutedText,
      divider: divider ?? this.divider,
      elevatedSurface: elevatedSurface ?? this.elevatedSurface,
      textOnImage: textOnImage ?? this.textOnImage,
      textOnImageMuted: textOnImageMuted ?? this.textOnImageMuted,
      scrim: scrim ?? this.scrim,
      scrimLight: scrimLight ?? this.scrimLight,
    );
  }

  @override
  TappedThemeExtension lerp(
    covariant ThemeExtension<TappedThemeExtension>? other,
    double t,
  ) {
    if (other is! TappedThemeExtension) return this;
    return TappedThemeExtension(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
      mutedText: Color.lerp(mutedText, other.mutedText, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      elevatedSurface: Color.lerp(elevatedSurface, other.elevatedSurface, t)!,
      textOnImage: Color.lerp(textOnImage, other.textOnImage, t)!,
      textOnImageMuted:
          Color.lerp(textOnImageMuted, other.textOnImageMuted, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      scrimLight: Color.lerp(scrimLight, other.scrimLight, t)!,
    );
  }
}

extension TappedThemeContext on BuildContext {
  /// Semantic colors for the current brightness.
  TappedThemeExtension get tokens =>
      Theme.of(this).extension<TappedThemeExtension>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? TappedThemeExtension.dark()
          : TappedThemeExtension.light());

  ColorScheme get colorScheme => Theme.of(this).colorScheme;

  TextTheme get textTheme => Theme.of(this).textTheme;

  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
}
