import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:formz/formz.dart';
import 'package:fpdart/fpdart.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intheloopapp/data/auth_repository.dart';
import 'package:intheloopapp/data/database_repository.dart';
import 'package:intheloopapp/data/places_repository.dart';
import 'package:intheloopapp/data/prod/firestore_database_impl.dart';
import 'package:intheloopapp/data/storage_repository.dart';
import 'package:intheloopapp/domains/authentication_bloc/authentication_bloc.dart';
import 'package:intheloopapp/domains/models/genre.dart';
import 'package:intheloopapp/domains/models/location.dart';
import 'package:intheloopapp/domains/models/performer_info.dart';
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/domains/models/username.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/onboarding_bloc/onboarding_bloc.dart';
import 'package:intheloopapp/utils/app_logger.dart';
import 'package:intheloopapp/utils/spotify_utils.dart';
import 'package:permission_handler/permission_handler.dart';

part 'settings_state.dart';

part 'settings_cubit.freezed.dart';

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit({
    required this.navigationBloc,
    required this.authenticationBloc,
    required this.onboardingBloc,
    required this.authRepository,
    required this.database,
    required this.storageRepository,
    required this.places,
    required this.currentUser,
  }) : super(
          SettingsState(
            formKey: GlobalKey<FormState>(debugLabel: 'settings'),
            pushNotificationsDirectMessages: currentUser.pushNotifications.directMessages,
            emailNotificationsAppReleases: currentUser.emailNotifications.appReleases,
            emailNotificationsDirectMessages: currentUser.emailNotifications.directMessages,
          ),
        );

  final UserModel currentUser;
  final NavigationBloc navigationBloc;
  final AuthenticationBloc authenticationBloc;
  final OnboardingBloc onboardingBloc;
  final AuthRepository authRepository;
  final DatabaseRepository database;
  final StorageRepository storageRepository;
  final PlacesRepository places;

  void initUserData() {
    emit(
      state.copyWith(
        isPerformer: currentUser.performerInfo.isSome(),
        username: currentUser.username.toString(),
        artistName: currentUser.artistName,
        bio: currentUser.bio,
        genres: fromStrings(
          currentUser.performerInfo.map((t) => t.genres).getOrElse(
                () => [],
              ),
        ),
        label: currentUser.performerInfo.toNullable()?.label ?? 'independent',
        occupations: currentUser.occupations,
        tiktokFollowers: currentUser.socialFollowing.tiktokFollowers,
        tiktokHandle: currentUser.socialFollowing.tiktokHandle.toNullable(),
        twitterFollowers: currentUser.socialFollowing.twitterFollowers,
        twitterHandle: currentUser.socialFollowing.twitterHandle.toNullable(),
        instagramFollowers: currentUser.socialFollowing.instagramFollowers,
        instagramHandle:
            currentUser.socialFollowing.instagramHandle.toNullable(),
        youtubeHandle:
            currentUser.socialFollowing.youtubeHandle.toNullable(),
        placeId: currentUser.location.toNullable()?.placeId,
        soundcloudHandle:
            currentUser.socialFollowing.soundcloudHandle.toNullable(),
        audiusHandle: currentUser.socialFollowing.audiusHandle.toNullable(),
        spotifyUrl: currentUser.socialFollowing.spotifyId.map((t) => 'https://open.spotify.com/artist/$t').toNullable(),
      ),
    );
  }

  Future<void> initPlace() async {
    try {
      final place = switch (currentUser.location) {
        None() => const None(),
        Some(:final value) => await places.getPlaceById(value.placeId),
      };
      emit(state.copyWith(place: place));
    } catch (e) {
      emit(state.copyWith());
    }
  }

  void changeBio(String value) => emit(state.copyWith(bio: value));

  void changeUsername(String value) => emit(state.copyWith(username: value));

  void changeArtistName(String value) =>
      emit(state.copyWith(artistName: value));

  void changeTwitter(String value) =>
      emit(state.copyWith(twitterHandle: value));

  void changeTwitterFollowers(int value) =>
      emit(state.copyWith(twitterFollowers: value));

  void changeInstagram(String value) =>
      emit(state.copyWith(instagramHandle: value));

  void changeInstagramFollowers(int value) => emit(
        state.copyWith(instagramFollowers: value),
      );

  void changeTikTik(String value) => emit(state.copyWith(tiktokHandle: value));

  void changeTikTokFollowers(int value) =>
      emit(state.copyWith(tiktokFollowers: value));

  void changeYoutube(String value) =>
      emit(state.copyWith(youtubeHandle: value));

  void changeSoundcloud(String value) =>
      emit(state.copyWith(soundcloudHandle: value));

  void changeSpotify(String value) =>
      emit(state.copyWith(spotifyUrl: value));

  void changePlace(Option<PlaceData> place, String placeId) {
    emit(
      state.copyWith(
        place: place,
        placeId: placeId,
      ),
    );
  }

  void changeGenres(List<Genre> genres) => emit(
        state.copyWith(genres: genres),
      );

  void removeGenre(Genre genre) {
    emit(
      state.copyWith(
        genres: state.genres..remove(genre),
      ),
    );
  }

  void changeOccupations(List<String> value) => emit(
        state.copyWith(occupations: value),
      );

  void removeOccupation(String occupation) {
    emit(
      state.copyWith(
        occupations: state.occupations..remove(occupation),
      ),
    );
  }

  void changeLabel(String? value) => emit(state.copyWith(label: value ?? ''));

  void updateEmail(String? input) => emit(
        state.copyWith(email: input ?? ''),
      );

  void updatePassword(String? input) => emit(
        state.copyWith(password: input ?? ''),
      );

  void changeDirectMsgPush({required bool selected}) =>
      emit(state.copyWith(pushNotificationsDirectMessages: selected));

  void changeAppReleaseEmail({required bool selected}) =>
      emit(state.copyWith(emailNotificationsAppReleases: selected));

  void changeDirectMessagesEmail({required bool selected}) =>
      emit(state.copyWith(emailNotificationsDirectMessages: selected));

  Future<void> handleImageFromGallery() async {
    try {
      await Permission.photos
          .onDeniedCallback(AppSettings.openAppSettings)
          .request()
          .then((status) {
        logger.debug('permission status: $status');
      });

      final imageFile =
          await ImagePicker().pickImage(source: ImageSource.gallery);
      if (imageFile != null) {
        emit(
          state.copyWith(
            profileImage: Option.of(
              File(imageFile.path),
            ),
          ),
        );
      }
    } catch (e) {
      // print(error);
    }
  }

  Future<void> pickPressKit() async {
    try {
      final file = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (file == null) {
        return;
      }

      final path = file.files.single.path;
      if (path == null) {
        return;
      }

      final user = currentUser.copyWith(
        performerInfo: currentUser.performerInfo.map(
          (t) => t.copyWith(
            pressKitUrl: Option.of(path),
          ),
        ),
      );
      onboardingBloc.add(UpdateOnboardedUser(user: user));

      emit(
        state.copyWith(
          pressKitFile: Option.of(File(path)),
        ),
      );
    } catch (e) {
      // print(e);
    }
  }

  void removePressKit() {
    emit(
      state.copyWith(
        pressKitFile: const None(),
      ),
    );
  }

  void changeIsPerformer(bool value) {
    emit(
      state.copyWith(
        isPerformer: value,
      ),
    );
  }


  Future<void> saveProfile() async {
    // print(state.formKey);
    if (state.formKey.currentState == null) {
      return;
    }

    try {
      if (state.formKey.currentState!.validate() &&
          !state.status.isInProgress) {
        emit(state.copyWith(status: FormzSubmissionStatus.inProgress));

        final available = await database.checkUsernameAvailability(
          state.username,
          currentUser.id,
        );

        if (!available) {
          throw HandleAlreadyExistsException('username already exists');
        }

        if (state.spotifyUrl != null) {
          if (!isValidSpotifyUrl(state.spotifyUrl!)) {
            throw const InvalidSpotifyUrlException('invalid spotify url');
          }
        }

        final profilePictureUrl = await switch (state.profileImage) {
          None() => Future<Option<String>>.value(currentUser.profilePicture),
          Some(:final value) => storageRepository
              .uploadProfilePicture(
                currentUser.id,
                value,
              )
              .then(Option.of),
        };

        final pressKitUrl = await switch (state.pressKitFile) {
          None() => Future<Option<String>>.value(
              currentUser.performerInfo.flatMap((t) => t.pressKitUrl),
            ),
          Some(:final value) => (() async {
              final url = await storageRepository.uploadPressKit(
                userId: currentUser.id,
                pressKitFile: value,
              );
              return Option.of(url);
            })(),
        };

        final location = switch (state.place) {
          None() => const None(),
          Some(:final value) => Option.of(
              Location(
                placeId: value.placeId,
                // geohash: value.geohash,
                lat: value.lat,
                lng: value.lng,
              ),
            ),
        };

        final newPerformerInfo = switch (currentUser.performerInfo) {
          None() => PerformerInfo(
              genres: state.genres.map((e) => e.name).toList(),
              label: state.label ?? 'Independent',
              pressKitUrl: pressKitUrl,
            ),
          Some(:final value) => value.copyWith(
              genres: state.genres.map((e) => e.name).toList(),
              label: state.label ?? 'Independent',
              pressKitUrl: pressKitUrl,
            ),
        };

        final spotifyId = state.spotifyUrl == null
          ? const None()
          : Uri.parse(state.spotifyUrl!).pathSegments.lastOption;
        final user = currentUser.copyWith(
          username: Username.fromString(state.username),
          artistName: state.artistName,
          bio: state.bio,
          performerInfo: state.isPerformer ? Option.of(newPerformerInfo) : const None(),
          socialFollowing: currentUser.socialFollowing.copyWith(
            twitterHandle: Option.fromNullable(state.twitterHandle),
            twitterFollowers: state.twitterFollowers ?? 0,
            instagramHandle: Option.fromNullable(state.instagramHandle),
            instagramFollowers: state.instagramFollowers ?? 0,
            tiktokHandle: Option.fromNullable(state.tiktokHandle),
            tiktokFollowers: state.tiktokFollowers ?? 0,
            youtubeHandle: Option.fromNullable(state.youtubeHandle),
            soundcloudHandle: Option.fromNullable(state.soundcloudHandle),
            spotifyId: spotifyId,
          ),
          pushNotifications: currentUser.pushNotifications.copyWith(
            directMessages: state.pushNotificationsDirectMessages,
          ),
          emailNotifications: currentUser.emailNotifications.copyWith(
            appReleases: state.emailNotificationsAppReleases,
            directMessages: state.emailNotificationsDirectMessages,
          ),
          location: location,
          profilePicture: profilePictureUrl,
          // stripeConnectedAccountId: state.stripeConnectedAccountId,
        );

        await database.updateUserData(user);
        onboardingBloc.add(UpdateOnboardedUser(user: user));
        emit(state.copyWith(status: FormzSubmissionStatus.success));
        navigationBloc.pop();
      } else {
        // print('invalid');
      }
    } catch (e) {
      emit(state.copyWith(status: FormzSubmissionStatus.failure));
      rethrow;
    }
  }

  Future<void> reauthWithGoogle() async {
    emit(
      state.copyWith(status: FormzSubmissionStatus.inProgress),
    );
    try {
      await authRepository.reauthenticateWithGoogle();
      await deleteUser();
      emit(
        state.copyWith(status: FormzSubmissionStatus.success),
      );
    } catch (e) {
      // print(e);
      emit(
        state.copyWith(status: FormzSubmissionStatus.failure),
      );
    }
  }

  Future<void> reauthWithApple() async {
    emit(
      state.copyWith(status: FormzSubmissionStatus.inProgress),
    );
    try {
      await authRepository.reauthenticateWithApple();
      await deleteUser();
      emit(
        state.copyWith(status: FormzSubmissionStatus.success),
      );
    } catch (e) {
      // print(e);
      emit(
        state.copyWith(status: FormzSubmissionStatus.failure),
      );
    }
  }

  Future<void> reauthWithCredentials() async {
    emit(
      state.copyWith(status: FormzSubmissionStatus.inProgress),
    );
    try {
      await authRepository.reauthenticateWithCredentials(
        state.email,
        state.password,
      );
      await deleteUser();
      emit(
        state.copyWith(status: FormzSubmissionStatus.success),
      );
    } catch (e) {
      // print(e);
      emit(
        state.copyWith(status: FormzSubmissionStatus.failure),
      );
    }
  }

  Future<void> deleteUser() async {
    await authRepository.deleteUser();
    authenticationBloc.add(LoggedOut());
    navigationBloc
      ..add(const Pop())
      ..add(const Pop());
  }
}
