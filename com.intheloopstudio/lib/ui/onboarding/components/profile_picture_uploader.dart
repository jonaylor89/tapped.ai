import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/domains/authentication_bloc/authentication_bloc.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/onboarding/onboarding_flow_cubit.dart';
import 'package:intheloopapp/utils/default_image.dart';

class ProfilePictureUploader extends StatelessWidget {
  const ProfilePictureUploader({super.key});

  ImageProvider displayProfileImage(
    Option<File> newProfileImage,
    Option<String> currentProfileImage,
  ) {
    return switch (newProfileImage) {
      Some(:final value) => FileImage(value),
      None() => switch (currentProfileImage) {
        Some(:final value) => CachedNetworkImageProvider(value),
        None() => getDefaultImage(const None()),
      },
    };
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthenticationBloc, AuthenticationState>(
      builder: (context, userState) {
        if (userState is! Authenticated) {
          return const CupertinoActivityIndicator();
        }

        return BlocBuilder<OnboardingFlowCubit, OnboardingFlowState>(
          builder: (context, state) {
            final image = switch (state.photoUrl) {
              None() => displayProfileImage(state.pickedPhoto, const None()),
              Some(:final value) => CachedNetworkImageProvider(value),
            };
            return Center(
              child: GlassPressable(
                semanticsLabel: 'upload profile picture',
                onPressed: context
                    .read<OnboardingFlowCubit>()
                    .handleImageFromGallery,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    LiquidGlass.circle(
                      width: 132,
                      height: 132,
                      padding: const EdgeInsets.all(5),
                      child: ClipOval(
                        child: Image(image: image, fit: BoxFit.cover),
                      ),
                    ),
                    LiquidGlass.circle(
                      width: 40,
                      height: 40,
                      tint: Theme.of(context).colorScheme.primary,
                      child: Center(
                        child: Icon(
                          CupertinoIcons.camera_fill,
                          size: 18,
                          color: glassTintForeground(
                            Theme.of(context).colorScheme.primary,
                            isDark:
                                Theme.of(context).brightness == Brightness.dark,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
