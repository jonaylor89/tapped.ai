import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/forms/email_text_field.dart';
import 'package:intheloopapp/ui/forms/password_text_field.dart';
import 'package:intheloopapp/ui/login/components/forgot_password_button.dart';
import 'package:intheloopapp/ui/login/components/login_button.dart';
import 'package:intheloopapp/ui/login/components/signup_button.dart';
import 'package:intheloopapp/ui/login/login_cubit.dart';

class TraditionalLogin extends StatelessWidget {
  const TraditionalLogin({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LoginCubit, LoginState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EmailTextField(
              onChanged: (input) =>
                  context.read<LoginCubit>().updateEmail(input ?? ''),
            ),
            const SizedBox(height: TappedSpacing.md),
            PasswordTextField(
              onChanged: (input) =>
                  context.read<LoginCubit>().updatePassword(input ?? ''),
            ),
            const Align(
              alignment: Alignment.centerRight,
              child: ForgotPasswordButton(),
            ),
            const SizedBox(height: TappedSpacing.sm),
            const LoginButton(),
            const SizedBox(height: TappedSpacing.sm),
            const SignUpButton(),
          ],
        );
      },
    );
  }
}
