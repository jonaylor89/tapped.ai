import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/login/components/auth_scaffold.dart';
import 'package:intheloopapp/ui/login/login_cubit.dart';

class ConfirmSignUpButton extends StatelessWidget {
  const ConfirmSignUpButton({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LoginCubit, LoginState>(
      builder: (context, state) {
        return GlassButton.primary(
          label: 'create account',
          expand: true,
          onPressed: () {
            context.read<LoginCubit>().signUpWithCredentials().onError((
              error,
              stackTrace,
            ) {
              if (!context.mounted) return;
              showAuthError(context, 'something went wrong :/');
            });
          },
        );
      },
    );
  }
}
