import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/tapped_theme_extension.dart';

class TappedCard extends StatelessWidget {
  const TappedCard({
    required this.child,
    this.padding,
    this.borderRadius,
    this.onTap,
    this.semanticsLabel,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;

  /// Announced by screen readers when the card is tappable.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = borderRadius ?? TappedRadius.lgAll;

    final content = Padding(
      padding: padding ?? const EdgeInsets.all(TappedSpacing.lg),
      child: child,
    );

    final card = Material(
      color: context.tokens.elevatedSurface,
      borderRadius: effectiveRadius,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: TappedSizes.minTapTarget,
                ),
                child: content,
              ),
            ),
    );

    if (onTap == null || semanticsLabel == null) return card;
    return Semantics(
      label: semanticsLabel,
      button: true,
      child: card,
    );
  }
}
