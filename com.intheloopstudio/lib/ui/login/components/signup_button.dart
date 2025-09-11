import 'package:flutter/cupertino.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';

class SignUpButton extends StatelessWidget {
  const SignUpButton({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      onPressed: () => {
        context.push(SignUpPage()),
      },
      child: const Text(
        'sign up',
        style: TextStyle(
          fontSize: 12,
        ),
      ),
    );
  }
}
