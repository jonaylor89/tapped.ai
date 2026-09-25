import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:formz/formz.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/forms/apple_login_button.dart';
import 'package:intheloopapp/ui/forms/email_text_field.dart';
import 'package:intheloopapp/ui/forms/google_login_button.dart';
import 'package:intheloopapp/ui/forms/password_text_field.dart';
import 'package:intheloopapp/ui/settings/components/reauthenticate_button.dart';
import 'package:intheloopapp/ui/settings/settings_cubit.dart';

class DeleteAccountButton extends StatelessWidget {
  const DeleteAccountButton({super.key});

  void _showReauth(BuildContext context) {
    final cubit = context.read<SettingsCubit>();
    showGlassSheet<void>(
      context: context,
      title: 'delete account',
      scrollable: true,
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: BlocBuilder<SettingsCubit, SettingsState>(
          builder: (context, state) {
            if (state.status.isInProgress) {
              return const Padding(
                padding: EdgeInsets.all(TappedSpacing.xl),
                child: GlassLoading(),
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const GlassBanner(
                  icon: CupertinoIcons.exclamationmark_triangle_fill,
                  tint: TappedColors.error,
                  title: 'this cannot be undone',
                  message:
                      'reauthenticate to permanently delete your '
                      'account and all of its data',
                ),
                const SizedBox(height: TappedSpacing.lg),
                EmailTextField(onChanged: cubit.updateEmail),
                const SizedBox(height: TappedSpacing.md),
                PasswordTextField(onChanged: cubit.updatePassword),
                const SizedBox(height: TappedSpacing.lg),
                ReauthenticateButton(onPressed: cubit.reauthWithCredentials),
                const SizedBox(height: TappedSpacing.lg),
                GoogleLoginButton(onPressed: cubit.reauthWithGoogle),
                if (Platform.isIOS) ...[
                  const SizedBox(height: TappedSpacing.sm),
                  AppleLoginButton(onPressed: cubit.reauthWithApple),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GlassButton.plain(
        label: 'delete account',
        icon: CupertinoIcons.trash,
        compact: true,
        onPressed: () => _showReauth(context),
      ),
    );
  }
}
