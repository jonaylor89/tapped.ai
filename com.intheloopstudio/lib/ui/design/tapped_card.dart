import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';

class TappedCard extends StatelessWidget {
  const TappedCard({
    required this.child,
    this.padding,
    this.borderRadius,
    this.onTap,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveRadius = borderRadius ?? TappedRadius.lgAll;

    final card = Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: effectiveRadius,
      ),
      padding: padding ??
          const EdgeInsets.all(TappedSpacing.lg),
      child: child,
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: card,
      );
    }

    return card;
  }
}
