import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';

/// A row in a settings [GlassSection].
class SettingsButton extends StatelessWidget {
  const SettingsButton({
    super.key,
    this.icon,
    this.iconColor,
    this.label,
    this.value,
    this.onTap,
    this.destructive = false,
  });

  final IconData? icon;
  final Color? iconColor;
  final String? label;
  final String? value;
  final void Function()? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return GlassListTile(
      leadingIcon: icon,
      leadingColor: iconColor,
      title: label ?? '',
      value: value,
      destructive: destructive,
      onTap: onTap,
    );
  }
}
