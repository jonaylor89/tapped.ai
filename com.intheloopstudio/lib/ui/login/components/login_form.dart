import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:formz/formz.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/forms/apple_login_button.dart';
import 'package:intheloopapp/ui/forms/google_login_button.dart';
import 'package:intheloopapp/ui/login/components/auth_scaffold.dart';
import 'package:intheloopapp/ui/login/components/traditional_login.dart';
import 'package:intheloopapp/ui/login/login_cubit.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';

class LoginForm extends StatelessWidget {
  const LoginForm({
    super.key,
  });

  Future<void> _social(
    BuildContext context,
    Future<void> Function() signIn,
  ) async {
    final nav = context.nav;
    try {
      await signIn();
      nav.pop();
    } catch (e) {
      if (!context.mounted) return;
      showAuthError(context, 'authentication failure');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<LoginCubit, LoginState>(
      listener: (context, state) {
        if (state.status.isFailure) {
          showAuthError(context, 'authentication failure');
          context.read<LoginCubit>().resetStatus();
        }
      },
      child: AuthScaffold(
        title: 'welcome back',
        subtitle:
            'log in with your email or a social account to get back '
            'in the action',
        children: [
          const TraditionalLogin(),
          const AuthDivider(),
          GoogleLoginButton(
            onPressed: () => _social(
              context,
              context.read<LoginCubit>().signInWithGoogle,
            ),
          ),
          if (!kIsWeb && Platform.isIOS) ...[
            const SizedBox(height: TappedSpacing.md),
            AppleLoginButton(
              onPressed: () => _social(
                context,
                context.read<LoginCubit>().signInWithApple,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
