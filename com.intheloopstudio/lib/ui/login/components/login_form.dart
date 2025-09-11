import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:formz/formz.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/ui/forms/apple_login_button.dart';
import 'package:intheloopapp/ui/forms/google_login_button.dart';
import 'package:intheloopapp/ui/login/components/traditional_login.dart';
import 'package:intheloopapp/ui/login/login_cubit.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';

class LoginForm extends StatelessWidget {
  const LoginForm({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final nav = context.nav;
    return BlocListener<LoginCubit, LoginState>(
      listener: (context, state) {
        if (state.status.isFailure) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                behavior: SnackBarBehavior.floating,
                backgroundColor: Colors.redAccent,
                content: Text('Authentication Failure'),
              ),
            );
          context.read<LoginCubit>().resetStatus();
        }
      },
      child: Align(
        alignment: const Alignment(0, -1 / 3),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'welcome back',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'login with your email or social media account to get back in the action',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
                const SizedBox(
                  height: 20,
                ),
                const TraditionalLogin(),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Divider(
                        height: 0,
                        thickness: 0.5,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'or',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Divider(
                        height: 0,
                        thickness: 0.5,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(
                  height: 20,
                ),
                GoogleLoginButton(
                  onPressed: () async {
                    final scaffoldMessenger = ScaffoldMessenger.of(context);
                    try {
                      await context.read<LoginCubit>().signInWithGoogle();
                      nav.pop();
                    } catch (e) {
                      scaffoldMessenger
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          const SnackBar(
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: Colors.redAccent,
                            content: Text('Authentication Failure'),
                          ),
                        );
                    }
                  },
                ),
                const SizedBox(height: 20),
                if (!kIsWeb && Platform.isIOS)
                  AppleLoginButton(
                    onPressed: () async {
                      final scaffoldMessenger = ScaffoldMessenger.of(context);
                      try {
                        await context.read<LoginCubit>().signInWithApple();
                        nav.pop();
                      } catch (e) {
                        scaffoldMessenger
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            const SnackBar(
                              behavior: SnackBarBehavior.floating,
                              backgroundColor: Colors.redAccent,
                              content: Text('authentication failure'),
                            ),
                          );
                      }
                    },
                  )
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
