import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/domains/authentication_bloc/authentication_bloc.dart';
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
          // ignore: unnecessary_cast
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
            return GestureDetector(
              onTap: () =>
                  context.read<OnboardingFlowCubit>().handleImageFromGallery(),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 45,
                        backgroundImage: switch (state.photoUrl) {
                          None() => displayProfileImage(
                              state.pickedPhoto,
                              const None(),
                            ),
                          Some(:final value) =>
                            CachedNetworkImageProvider(value),
                        },
                      ),
                      const CircleAvatar(
                        radius: 45,
                        backgroundColor: Colors.black54,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Icon(
                              Icons.camera_alt,
                              size: 50,
                              color: Colors.white,
                            ),
                            Text(
                              'Upload Profile Picture',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
