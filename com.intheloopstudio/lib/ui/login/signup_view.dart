import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/ui/forms/apple_login_button.dart';
import 'package:intheloopapp/ui/forms/email_text_field.dart';
import 'package:intheloopapp/ui/forms/google_login_button.dart';
import 'package:intheloopapp/ui/forms/password_text_field.dart';
import 'package:intheloopapp/ui/login/components/confirm_signup_button.dart';
import 'package:intheloopapp/ui/login/login_cubit.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/login/components/auth_scaffold.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:url_launcher/url_launcher.dart';

class SignUpView extends StatelessWidget {
  const SignUpView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocProvider(
      create: (context) => LoginCubit(
        auth: context.auth,
        nav: context.nav,
      ),
      child: BlocBuilder<LoginCubit, LoginState>(
        builder: (context, state) {
          final cubit = context.read<LoginCubit>();
          return AuthScaffold(
            title: "let's get started",
            subtitle: 'first, create an account to get you set up',
            footer: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                GlassButton.plain(
                  label: 'privacy policy',
                  compact: true,
                  onPressed: () => launchUrl(
                    Uri(scheme: 'https', path: 'tapped.ai/privacy'),
                  ),
                ),
                Text(
                  '·',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
                GlassButton.plain(
                  label: 'terms of service',
                  compact: true,
                  onPressed: () => launchUrl(
                    Uri(
                      scheme: 'https',
                      path:
                          'www.apple.com/legal/internet-services/itunes/dev/stdeula/',
                    ),
                  ),
                ),
              ],
            ),
            children: [
              EmailTextField(
                onChanged: (input) => cubit.updateEmail(input ?? ''),
              ),
              const SizedBox(height: TappedSpacing.md),
              PasswordTextField(
                textInputAction: TextInputAction.next,
                onChanged: (input) => cubit.updatePassword(input ?? ''),
              ),
              const SizedBox(height: TappedSpacing.md),
              PasswordTextField(
                labelText: 'confirm password',
                onChanged: (input) => cubit.updateConfirmPassword(input ?? ''),
              ),
              const SizedBox(height: TappedSpacing.xl),
              const ConfirmSignUpButton(),
              const AuthDivider(),
              GoogleLoginButton(
                onPressed: () {
                  cubit.signInWithGoogle().onError((error, stackTrace) {
                    if (!context.mounted) return;
                    showAuthError(context, 'could not sign in with Google');
                  });
                },
              ),
              if (Platform.isIOS) ...[
                const SizedBox(height: TappedSpacing.md),
                AppleLoginButton(
                  onPressed: () {
                    cubit.signInWithApple().onError((error, stackTrace) {
                      if (!context.mounted) return;
                      showAuthError(context, 'could not sign in with Apple');
                    });
                    context.pop();
                  },
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
