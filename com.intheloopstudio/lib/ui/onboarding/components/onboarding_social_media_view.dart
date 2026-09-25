import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/forms/instagram_followers_text_field.dart';
import 'package:intheloopapp/ui/forms/instagram_text_field.dart';
import 'package:intheloopapp/ui/forms/tiktok_followers_text_field.dart';
import 'package:intheloopapp/ui/forms/tiktok_text_field.dart';
import 'package:intheloopapp/ui/onboarding/onboarding_flow_cubit.dart';

class OnboardingSocialMediaView extends StatelessWidget {
  const OnboardingSocialMediaView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocBuilder<OnboardingFlowCubit, OnboardingFlowState>(
      builder: (context, state) {
        final cubit = context.read<OnboardingFlowCubit>();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'what are your socials?',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
              ),
            ),
            const SizedBox(height: TappedSpacing.xs),
            Text(
              'optional — helps bookers gauge your reach',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: TappedSpacing.xl),
            GlassFormGroup(
              header: 'tiktok',
              margin: EdgeInsets.zero,
              children: [
                TikTokTextField(
                  onChanged: cubit.tiktokHandleChange,
                  initialValue: state.tiktokHandle,
                ),
                TikTokFollowersTextField(
                  onChanged: cubit.tiktokFollowersChange,
                  initialValue: state.tiktokFollowers,
                ),
              ],
            ),
            const SizedBox(height: TappedSpacing.lg),
            GlassFormGroup(
              header: 'instagram',
              margin: EdgeInsets.zero,
              children: [
                InstagramTextField(
                  onChanged: cubit.instagramHandleChange,
                  initialValue: state.instagramHandle,
                ),
                InstagramFollowersTextField(
                  onChanged: cubit.instagramFollowersChange,
                  initialValue: state.instagramFollowers,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
