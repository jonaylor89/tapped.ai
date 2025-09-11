import 'package:flutter/cupertino.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';

class ForgotPasswordButton extends StatelessWidget {
  const ForgotPasswordButton({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      onPressed: () => {
        context.push(ForgotPasswordPage()),
      },
      child: const Text(
        'forgot password?',
        style: TextStyle(
          fontSize: 12,
        ),
      ),
    );
  }
}
