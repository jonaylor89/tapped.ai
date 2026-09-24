import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:intheloopapp/ui/app_theme_cubit.dart';
import 'package:mockito/mockito.dart';

class MockStorage extends Mock implements Storage {
  @override
  Future<void> write(String key, dynamic value) async {}

  @override
  dynamic read(String key) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HydratedBloc.storage = MockStorage();

  group('AppThemeCubit', () {
    blocTest<AppThemeCubit, ThemeMode>(
      'defaults to following the system theme',
      build: AppThemeCubit.new,
      verify: (cubit) => expect(cubit.state, ThemeMode.system),
      expect: () => <ThemeMode>[],
    );

    blocTest<AppThemeCubit, ThemeMode>(
      'emits dark when theme updated to dark',
      build: AppThemeCubit.new,
      act: (cubit) => cubit.updateTheme(isDarkMode: true),
      expect: () => [ThemeMode.dark],
    );

    blocTest<AppThemeCubit, ThemeMode>(
      'emits light when theme updated to light',
      build: AppThemeCubit.new,
      act: (cubit) => cubit.updateTheme(isDarkMode: false),
      expect: () => [ThemeMode.light],
    );

    blocTest<AppThemeCubit, ThemeMode>(
      'emits system when explicitly chosen',
      build: AppThemeCubit.new,
      seed: () => ThemeMode.dark,
      act: (cubit) => cubit.updateThemeMode(ThemeMode.system),
      expect: () => [ThemeMode.system],
    );

    test('round-trips through json', () {
      final cubit = AppThemeCubit();
      for (final mode in ThemeMode.values) {
        expect(cubit.fromJson(cubit.toJson(mode)), mode);
      }
    });

    test('migrates the legacy isDark payload', () {
      final cubit = AppThemeCubit();
      expect(cubit.fromJson({'isDark': true}), ThemeMode.dark);
      expect(cubit.fromJson({'isDark': false}), ThemeMode.light);
      expect(cubit.fromJson(<String, dynamic>{}), ThemeMode.system);
    });
  });
}
