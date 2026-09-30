import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intheloopapp/domains/models/spotify_artist.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/onboarding/components/onboard_with_spotify_view.dart';
import 'package:intheloopapp/ui/onboarding/onboarding_flow_cubit.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';

class OnboardWithSpotifyButton extends StatelessWidget {
  const OnboardWithSpotifyButton({
    this.initialValue,
    this.onChanged,
    super.key,
  });

  final String? initialValue;
  final void Function(SpotifyArtist)? onChanged;

  static const _spotifyGreen = Color(0xff1DB954);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OnboardingFlowCubit, OnboardingFlowState>(
      builder: (context, state) {
        return GlassButton(
          label: 'import from Spotify',
          icon: FontAwesomeIcons.spotify,
          foreground: _spotifyGreen,
          expand: true,
          onPressed: () {
            showCupertinoModalBottomSheet<void>(
              context: context,
              builder: (context) {
                return OnboardWithSpotifyView(
                  initialValue: initialValue,
                  onChanged: onChanged,
                );
              },
            );
          },
        );
      },
    );
  }
}
