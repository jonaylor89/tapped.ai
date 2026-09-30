import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/onboarding/components/eula_button.dart';
import 'package:intheloopapp/ui/onboarding/onboarding_flow_cubit.dart';

class OnboardingCompleteView extends StatelessWidget {
  const OnboardingCompleteView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocBuilder<OnboardingFlowCubit, OnboardingFlowState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(GlassRadius.sheet),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const Image(
                      image: AssetImage('assets/splash.gif'),
                      fit: BoxFit.cover,
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.7),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: TappedSpacing.xl,
                      right: TappedSpacing.xl,
                      bottom: TappedSpacing.xl,
                      child: Text(
                        "you're all set",
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: TappedSpacing.xl),
            Text(
              'you can edit your profile any time from settings. want to get '
              'verified? post a screenshot of your profile to your instagram '
              'story and tag @tappedai.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                height: 1.4,
              ),
            ),
            const SizedBox(height: TappedSpacing.xl),
            EULAButton(
              initialValue: state.eula,
              onChanged: (input) => context
                  .read<OnboardingFlowCubit>()
                  .eulaChange(input ?? false),
            ),
          ],
        );
      },
    );
  }
}
