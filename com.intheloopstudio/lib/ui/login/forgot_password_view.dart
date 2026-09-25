import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/forms/email_text_field.dart';
import 'package:intheloopapp/ui/login/components/auth_scaffold.dart';
import 'package:intheloopapp/ui/login/login_cubit.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';

class ForgotPasswordView extends StatefulWidget {
  const ForgotPasswordView({super.key});

  @override
  State<ForgotPasswordView> createState() => _ForgotPasswordViewState();
}

class _ForgotPasswordViewState extends State<ForgotPasswordView> {
  bool linkSent = false;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => LoginCubit(
        auth: context.auth,
        nav: context.nav,
      ),
      child: BlocBuilder<LoginCubit, LoginState>(
        builder: (context, state) {
          if (linkSent) {
            return AuthScaffold(
              title: 'check your inbox',
              subtitle: 'we sent a password reset link to ${state.email}',
              children: [
                GlassEmptyState(
                  icon: CupertinoIcons.envelope_open,
                  title: 'link sent',
                  message: "didn't get it? check spam or try again",
                  actionLabel: 'back to log in',
                  onAction: () => Navigator.of(context).maybePop(),
                ),
              ],
            );
          }

          return AuthScaffold(
            title: 'reset password',
            subtitle:
                "enter the email on your account and we'll send you a "
                'link to reset your password',
            children: [
              EmailTextField(
                textInputAction: TextInputAction.done,
                onChanged: context.read<LoginCubit>().updateEmail,
              ),
              const SizedBox(height: TappedSpacing.xl),
              GlassButton.primary(
                label: 'send reset link',
                icon: CupertinoIcons.paperplane_fill,
                expand: true,
                onPressed: () {
                  context.read<LoginCubit>().sendResetPasswordLink();
                  setState(() {
                    linkSent = true;
                  });
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
