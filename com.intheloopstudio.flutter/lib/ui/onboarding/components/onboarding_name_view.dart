import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/domains/models/spotify_artist.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/forms/artist_name_text_field.dart';
import 'package:intheloopapp/ui/login/components/auth_scaffold.dart';
import 'package:intheloopapp/ui/onboarding/components/onboard_with_spotify_button.dart';
import 'package:intheloopapp/ui/onboarding/onboarding_flow_cubit.dart';

class OnboardingUsernameView extends StatelessWidget {
  const OnboardingUsernameView({super.key});

  Widget _spotifyPreview(BuildContext context, SpotifyArtist value) {
    final theme = Theme.of(context);
    final cubit = context.read<OnboardingFlowCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: TappedSpacing.xl),
        Center(
          child: LiquidGlass.circle(
            width: 180,
            height: 180,
            padding: const EdgeInsets.all(6),
            child: ClipOval(
              child: value.images.isNotEmpty
                  ? Image(
                      image: CachedNetworkImageProvider(value.images.first.url),
                      fit: BoxFit.cover,
                    )
                  : Icon(
                      CupertinoIcons.music_mic,
                      size: 56,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
            ),
          ),
        ),
        const SizedBox(height: TappedSpacing.xl),
        Text(
          value.name.getOrElse(() => 'artist name unknown'),
          textAlign: TextAlign.center,
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: TappedSpacing.sm),
        Text(
          'pulled from spotify',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        if (value.genres.isNotEmpty) ...[
          const SizedBox(height: TappedSpacing.lg),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: TappedSpacing.sm,
            runSpacing: TappedSpacing.sm,
            children: [
              for (final genre in value.genres) GlassPill(label: genre),
            ],
          ),
        ],
        const SizedBox(height: TappedSpacing.xl),
        Center(
          child: GlassButton.plain(
            label: 'use a different name',
            compact: true,
            onPressed: () => cubit.spotifyArtistChange(const None()),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocBuilder<OnboardingFlowCubit, OnboardingFlowState>(
      builder: (context, state) {
        final cubit = context.read<OnboardingFlowCubit>();
        return switch (state.spotifyArtist) {
          Some(:final value) => _spotifyPreview(context, value),
          None() => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "what's your performer name?",
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: TappedSpacing.xs),
              Text(
                'e.g. DJ Drama, Doja Cat — this is what venues will see',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: TappedSpacing.xl),
              ArtistNameTextField(
                onChanged: (input) => cubit.artistNameChange(input ?? ''),
                initialValue: state.artistName,
              ),
              const AuthDivider(),
              OnboardWithSpotifyButton(
                initialValue: state.spotifyArtist
                    .map((s) => s.id)
                    .fold(
                      () => '',
                      (a) => 'https://open.spotify.com/artist/$a',
                    ),
                onChanged: (value) =>
                    cubit.spotifyArtistChange(Option.of(value)),
              ),
            ],
          ),
        };
      },
    );
  }
}
