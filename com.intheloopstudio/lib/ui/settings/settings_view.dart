import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intheloopapp/ui/settings/components/action_menu.dart';
import 'package:intheloopapp/ui/settings/components/change_profile_image.dart';
import 'package:intheloopapp/ui/settings/components/delete_account_button.dart';
import 'package:intheloopapp/ui/settings/components/dev_information.dart';
import 'package:intheloopapp/ui/settings/components/notification_settings_form.dart';
import 'package:intheloopapp/ui/settings/components/payment_settings_form.dart';
import 'package:intheloopapp/ui/settings/components/save_button.dart';
import 'package:intheloopapp/ui/settings/components/settings_form.dart';
import 'package:intheloopapp/ui/settings/settings_cubit.dart';
import 'package:intheloopapp/ui/themes.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:intheloopapp/utils/current_user_builder.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CurrentUserBuilder(
      builder: (context, currentUser) {
        return BlocProvider(
          create: (_) => SettingsCubit(
            authenticationBloc: context.authentication,
            onboardingBloc: context.onboarding,
            authRepository: context.auth,
            database: context.database,
            storageRepository: context.storage,
            navigationBloc: context.nav,
            places: context.places,
            currentUser: currentUser,
          )
            ..initUserData()
            ..initPlace(),
          child: Scaffold(
            backgroundColor: theme.colorScheme.surface,
            appBar: AppBar(
              title: Row(
                children: [
                  Text(
                    currentUser.artistName.isNotEmpty
                        ? currentUser.artistName
                        : currentUser.username.toString(),
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              elevation: 0,
            ),
            body: ListView(
              physics: const ClampingScrollPhysics(),
              children: [
                Stack(
                  children: [
                    Container(
                      height: 75,
                      decoration: const BoxDecoration(
                        color: tappedAccent,
                      ),
                    ),
                  ],
                ),
                Container(
                  transform: Matrix4.translationValues(0, -40, 0),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: const Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          ChangeProfileImage(),
                          SaveButton(),
                        ],
                      ),
                      // SizedBox(height: 20),
                      // Text(
                      //   'Payments',
                      //   style: TextStyle(
                      //     fontWeight: FontWeight.bold,
                      //     fontSize: 22,
                      //   ),
                      // ),
                      // SizedBox(height: 10),
                      // PaymentSettingsForm(),
                      SizedBox(height: 20),
                      Text(
                        'preferences',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                        ),
                      ),
                      SizedBox(height: 10),
                      SettingsForm(),
                      SizedBox(height: 30),
                      Text(
                        'notifications',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                        ),
                      ),
                      SizedBox(height: 10),
                      NotificationSettingsForm(),
                      SizedBox(height: 30),
                      Text(
                        'more options',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                        ),
                      ),
                      SizedBox(height: 10),
                      ActionMenu(),
                      SizedBox(height: 20),
                      DevInformation(),
                      SizedBox(height: 40),
                      DeleteAccountButton(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
