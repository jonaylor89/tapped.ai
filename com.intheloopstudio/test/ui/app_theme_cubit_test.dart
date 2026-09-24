import 'package:bloc_test/bloc_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:intheloopapp/ui/app_theme_cubit.dart';

class FakeFirebaseCore implements TestFirebaseCoreHostApi {
  static final _options = CoreFirebaseOptions(
    apiKey: 'test',
    projectId: 'test',
    appId: 'test',
    messagingSenderId: 'test',
  );

  CoreInitializeResponse _response(String name) => CoreInitializeResponse(
        name: name,
        options: _options,
        pluginConstants: {
          'plugins.flutter.io/firebase_crashlytics': {
            'isCrashlyticsCollectionEnabled': false,
          },
        },
      );

  @override
  Future<CoreInitializeResponse> initializeApp(
    String appName,
    CoreFirebaseOptions initializeAppRequest,
  ) async =>
      _response(appName);

  @override
  Future<List<CoreInitializeResponse>> initializeCore() async =>
      [_response(defaultFirebaseAppName)];

  @override
  Future<CoreFirebaseOptions> optionsFromResource() async => _options;
}

class InMemoryStorage implements Storage {
  final Map<String, dynamic> _data = {};

  @override
  dynamic read(String key) => _data[key];

  @override
  Future<void> write(String key, dynamic value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<void> clear() async => _data.clear();

  @override
  Future<void> close() async {}
}

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestFirebaseCoreHostApi.setUp(FakeFirebaseCore());
  await Firebase.initializeApp();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/firebase_crashlytics'),
    (_) async => null,
  );
  HydratedBloc.storage = InMemoryStorage();

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
