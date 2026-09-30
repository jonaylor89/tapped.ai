import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intheloopapp/ui/design/tapped_theme_extension.dart';
import 'package:intheloopapp/ui/themes.dart';

void main() {
  group('buildTheme', () {
    for (final brightness in Brightness.values) {
      test('${brightness.name} theme registers TappedThemeExtension', () {
        final theme = buildTheme(brightness: brightness);
        expect(theme.brightness, brightness);
        expect(theme.extension<TappedThemeExtension>(), isNotNull);
      });

      test('${brightness.name} slider track has visible progress', () {
        final theme = buildTheme(brightness: brightness);
        expect(
          theme.sliderTheme.activeTrackColor,
          isNot(theme.sliderTheme.inactiveTrackColor),
        );
      });

      test('${brightness.name} tab bar distinguishes selected label', () {
        final theme = buildTheme(brightness: brightness);
        expect(
          theme.tabBarTheme.labelColor,
          isNot(theme.tabBarTheme.unselectedLabelColor),
        );
      });
    }
  });

  testWidgets('context.tokens follows MaterialApp brightness', (tester) async {
    late TappedThemeExtension tokens;
    late bool isDark;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: ThemeMode.dark,
        home: Builder(
          builder: (context) {
            tokens = context.tokens;
            isDark = context.isDarkMode;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(isDark, isTrue);
    expect(tokens.elevatedSurface, TappedThemeExtension.dark().elevatedSurface);
  });
}
