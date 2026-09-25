import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';

class SettingsSwitch extends StatelessWidget {
  const SettingsSwitch({
    required this.label,
    required this.activated,
    required this.onChanged,
    this.icon,
    this.iconColor,
    super.key,
  });

  final String label;
  final bool activated;
  final IconData? icon;
  final Color? iconColor;
  // ignore: avoid_positional_boolean_parameters
  final void Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    return GlassSwitchTile(
      title: label,
      value: activated,
      leadingIcon: icon,
      leadingColor: iconColor,
      onChanged: onChanged,
    );
  }
}
