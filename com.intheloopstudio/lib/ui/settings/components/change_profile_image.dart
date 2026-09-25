import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/settings/settings_cubit.dart';
import 'package:intheloopapp/utils/current_user_builder.dart';
import 'package:intheloopapp/utils/default_image.dart';

/// Large avatar with a floating glass camera badge, like the iOS Contacts
/// "edit photo" affordance.
class ChangeProfileImage extends StatelessWidget {
  const ChangeProfileImage({super.key});

  ImageProvider displayProfileImage(
    Option<File> newProfileImage,
    Option<String> currentProfileImage,
  ) {
    return switch ((newProfileImage, currentProfileImage)) {
      (Some(:final value), _) => FileImage(value) as ImageProvider,
      (None(), Some(:final value)) => CachedNetworkImageProvider(value),
      (None(), None()) => getDefaultImage(const None()),
    };
  }

  @override
  Widget build(BuildContext context) {
    return CurrentUserBuilder(
      errorWidget: const Center(
        child: Text('An error has occured :/'),
      ),
      builder: (context, currentUser) {
        return BlocBuilder<SettingsCubit, SettingsState>(
          builder: (context, state) {
            return GlassPressable(
              semanticsLabel: 'change profile picture',
              onPressed: () =>
                  context.read<SettingsCubit>().handleImageFromGallery(),
              child: SizedBox(
                width: 116,
                height: 116,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          backgroundImage: displayProfileImage(
                            state.profileImage,
                            currentUser.profilePicture,
                          ),
                        ),
                      ),
                    ),
                    const Positioned(
                      right: 0,
                      bottom: 0,
                      child: LiquidGlass.circle(
                        width: 38,
                        height: 38,
                        variant: GlassVariant.prominent,
                        child: Center(
                          child: Icon(CupertinoIcons.camera_fill, size: 18),
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
