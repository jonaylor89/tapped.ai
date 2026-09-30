import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/login/components/auth_scaffold.dart';
import 'package:intheloopapp/ui/login/login_cubit.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';

class LoginButton extends StatelessWidget {
  const LoginButton({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = context.nav;
    return BlocBuilder<LoginCubit, LoginState>(
      builder: (context, state) {
        return GlassButton.primary(
          label: 'log in',
          expand: true,
          onPressed: () async {
            try {
              await context.read<LoginCubit>().signInWithCredentials();
              nav.pop();
            } catch (e) {
              if (!context.mounted) return;
              showAuthError(context, e.toString());
            }
          },
        );
      },
    );
  }
}
