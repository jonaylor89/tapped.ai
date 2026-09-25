import 'package:flutter/material.dart';
import 'package:intheloopapp/domains/authentication_bloc/authentication_bloc.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';

class OnboardingInitView extends StatelessWidget {
  const OnboardingInitView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: TappedSpacing.xl),
        Text(
          "let's get you set up",
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: TappedSpacing.sm),
        Text(
          'this info helps you get booked',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const Spacer(),
        Center(
          child: GlassButton.plain(
            label: 'sign into a different account?',
            compact: true,
            onPressed: () => context.authentication.add(LoggedOut()),
          ),
        ),
      ],
    );
  }
}
