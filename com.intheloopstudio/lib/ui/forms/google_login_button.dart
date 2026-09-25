import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';

class GoogleLoginButton extends StatelessWidget {
  const GoogleLoginButton({super.key, this.onPressed});

  final void Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    return GlassButton(
      label: 'continue with Google',
      icon: FontAwesomeIcons.google,
      expand: true,
      onPressed: onPressed,
    );
  }
}
