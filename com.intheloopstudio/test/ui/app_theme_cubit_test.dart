import 'package:bloc_test/bloc_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
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
    blocTest<AppThemeCubit, bool>(
      'emit `true` when theme updated to dark',
      build: AppThemeCubit.new,
      expect: () => <bool>[],
    );

    blocTest<AppThemeCubit, bool>(
      'emit `true` when theme updated to dark',
      build: AppThemeCubit.new,
      act: (AppThemeCubit bloc) => bloc.updateTheme(isDarkMode: true),
      expect: () => [true],
    );

    blocTest<AppThemeCubit, bool>(
      'emit `false` when theme updated to light',
      build: AppThemeCubit.new,
      act: (AppThemeCubit bloc) => bloc.updateTheme(isDarkMode: false),
      expect: () => [false],
    );
  });
}
