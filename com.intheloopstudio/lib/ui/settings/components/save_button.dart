import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:formz/formz.dart';
import 'package:intheloopapp/data/prod/firestore_database_impl.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/settings/settings_cubit.dart';
import 'package:intheloopapp/utils/app_logger.dart';
import 'package:intheloopapp/utils/spotify_utils.dart';

class SaveButton extends StatelessWidget {
  const SaveButton({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        return GlassButton.primary(
          label: 'save',
          compact: true,
          isLoading: state.status.isInProgress,
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            try {
              await context.read<SettingsCubit>().saveProfile();
              await HapticFeedback.mediumImpact();
            } on HandleAlreadyExistsException {
              _error(messenger, 'username already exists');
            } on InvalidSpotifyUrlException {
              _error(messenger, 'invalid spotify URL');
            } catch (e, s) {
              logger.error('error saving profile', error: e, stackTrace: s);
              _error(messenger, 'error saving profile');
            }
          },
        );
      },
    );
  }

  void _error(ScaffoldMessengerState messenger, String message) {
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red,
        content: Text(message, style: const TextStyle(color: Colors.white)),
      ),
    );
  }
}
