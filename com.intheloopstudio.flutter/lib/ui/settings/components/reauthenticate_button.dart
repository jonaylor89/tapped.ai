import 'package:flutter/cupertino.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';

class ReauthenticateButton extends StatelessWidget {
  const ReauthenticateButton({this.onPressed, super.key});

  final void Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    return GlassButton.primary(
      label: 'reauthenticate',
      icon: CupertinoIcons.lock_shield,
      onPressed: onPressed,
    );
  }
}
