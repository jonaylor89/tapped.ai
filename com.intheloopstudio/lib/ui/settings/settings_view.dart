import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/settings/components/action_menu.dart';
import 'package:intheloopapp/ui/settings/components/change_profile_image.dart';
import 'package:intheloopapp/ui/settings/components/delete_account_button.dart';
import 'package:intheloopapp/ui/settings/components/dev_information.dart';
import 'package:intheloopapp/ui/settings/components/notification_settings_form.dart';
import 'package:intheloopapp/ui/settings/components/save_button.dart';
import 'package:intheloopapp/ui/settings/components/settings_form.dart';
import 'package:intheloopapp/ui/settings/settings_cubit.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:intheloopapp/utils/current_user_builder.dart';

/// Account + preferences. A large-title glass page whose content is a stack
/// of inset grouped sections, with the save action floating in the nav row.
class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
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
          child: GlassPage(
            title: 'settings',
            subtitle: currentUser.artistName.isNotEmpty
                ? currentUser.artistName
                : '@${currentUser.username}',
            actions: const [SaveButton()],
            slivers: const [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: TappedSpacing.md),
                  child: Center(child: ChangeProfileImage()),
                ),
              ),
              SliverToBoxAdapter(child: SettingsForm()),
              SliverToBoxAdapter(child: NotificationSettingsForm()),
              SliverToBoxAdapter(child: ActionMenu()),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: TappedSpacing.xl),
                  child: DevInformation(),
                ),
              ),
              SliverToBoxAdapter(child: DeleteAccountButton()),
              SliverToBoxAdapter(
                child: SizedBox(height: GlassMetrics.bottomBarClearance),
              ),
            ],
          ),
        );
      },
    );
  }
}
