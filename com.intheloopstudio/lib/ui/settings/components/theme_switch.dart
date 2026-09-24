import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intheloopapp/ui/app_theme_cubit.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';

class ThemeSwitch extends StatelessWidget {
  const ThemeSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppThemeCubit, ThemeMode>(
      builder: (context, mode) {
        return Semantics(
          label: 'appearance',
          value: mode.name,
          child: CupertinoSlidingSegmentedControl<ThemeMode>(
            groupValue: mode,
            onValueChanged: (value) {
              if (value == null) return;
              context.read<AppThemeCubit>().updateThemeMode(value);
            },
            children: const {
              ThemeMode.system: _ThemeSegment(
                icon: FontAwesomeIcons.circleHalfStroke,
                label: 'auto',
              ),
              ThemeMode.light: _ThemeSegment(
                icon: FontAwesomeIcons.solidSun,
                label: 'light',
              ),
              ThemeMode.dark: _ThemeSegment(
                icon: FontAwesomeIcons.solidMoon,
                label: 'dark',
              ),
            },
          ),
        );
      },
    );
  }
}

class _ThemeSegment extends StatelessWidget {
  const _ThemeSegment({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TappedSpacing.md,
        vertical: TappedSpacing.sm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: TappedSpacing.sm),
          Text(label, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}
