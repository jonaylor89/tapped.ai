import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';

class AppleLoginButton extends StatelessWidget {
  const AppleLoginButton({super.key, this.onPressed});

  final void Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    return GlassButton(
      label: 'continue with Apple',
      icon: FontAwesomeIcons.apple,
      expand: true,
      onPressed: onPressed,
    );
  }
}
