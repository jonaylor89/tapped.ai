import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';

class TappedSectionHeader extends StatelessWidget {
  const TappedSectionHeader(
    this.title, {
    this.trailing,
    this.padding,
    super.key,
  });

  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ??
          const EdgeInsets.symmetric(
            vertical: TappedSpacing.lg,
            horizontal: TappedSpacing.sm,
          ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              style: TappedTypography.headingLg,
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
