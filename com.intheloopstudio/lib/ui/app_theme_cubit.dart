import 'package:flutter/material.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

/// The Cubit responsible for choosing the app's [ThemeMode].
///
/// Defaults to [ThemeMode.system] so the app follows the OS setting until the
/// user explicitly picks light or dark.
class AppThemeCubit extends HydratedCubit<ThemeMode> {
  AppThemeCubit() : super(ThemeMode.system);

  @override
  ThemeMode fromJson(Map<String, dynamic> json) {
    final mode = json['mode'];
    if (mode is String) {
      return ThemeMode.values.firstWhere(
        (m) => m.name == mode,
        orElse: () => ThemeMode.system,
      );
    }

    // Legacy payload from when the cubit stored a bare `isDark` flag.
    final isDark = json['isDark'];
    if (isDark is bool) {
      return isDark ? ThemeMode.dark : ThemeMode.light;
    }

    return ThemeMode.system;
  }

  @override
  Map<String, dynamic> toJson(ThemeMode state) => {'mode': state.name};

  void updateThemeMode(ThemeMode mode) => emit(mode);

  /// Convenience for callers that only know about light/dark.
  void updateTheme({required bool isDarkMode}) {
    updateThemeMode(isDarkMode ? ThemeMode.dark : ThemeMode.light);
  }
}
