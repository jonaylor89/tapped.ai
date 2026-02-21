import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';

enum TappedButtonVariant { filled, outline, text }

class TappedButton extends StatelessWidget {
  const TappedButton({
    required this.onPressed,
    required this.child,
    this.variant = TappedButtonVariant.filled,
    this.color,
    this.isLoading = false,
    super.key,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final TappedButtonVariant variant;
  final Color? color;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor = color ?? theme.colorScheme.primary;

    if (isLoading) {
      return const CupertinoButton(
        onPressed: null,
        child: CupertinoActivityIndicator(),
      );
    }

    return switch (variant) {
      TappedButtonVariant.filled => CupertinoButton(
          onPressed: onPressed,
          color: effectiveColor,
          borderRadius: TappedRadius.lgAll,
          child: DefaultTextStyle(
            style: TextStyle(
              color: theme.colorScheme.onPrimary,
              fontWeight: FontWeight.w600,
            ),
            child: child,
          ),
        ),
      TappedButtonVariant.outline => CupertinoButton(
          onPressed: onPressed,
          borderRadius: TappedRadius.lgAll,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: TappedRadius.lgAll,
              border: Border.all(color: effectiveColor),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: TappedSpacing.lg,
              vertical: TappedSpacing.sm,
            ),
            child: DefaultTextStyle(
              style: TextStyle(
                color: effectiveColor,
                fontWeight: FontWeight.w600,
              ),
              child: child,
            ),
          ),
        ),
      TappedButtonVariant.text => CupertinoButton(
          onPressed: onPressed,
          child: DefaultTextStyle(
            style: TextStyle(
              color: effectiveColor,
              fontWeight: FontWeight.w600,
            ),
            child: child,
          ),
        ),
    };
  }
}
