import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';

enum TappedButtonVariant { filled, outline, text }

/// The one button. Wraps Material's [FilledButton] / [OutlinedButton] /
/// [TextButton] so the styling lives in `themes.dart`, and guarantees a
/// 44pt minimum tap target plus a semantics label.
class TappedButton extends StatelessWidget {
  const TappedButton({
    required this.onPressed,
    required this.child,
    this.variant = TappedButtonVariant.filled,
    this.color,
    this.isLoading = false,
    this.expand = false,
    this.semanticsLabel,
    super.key,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final TappedButtonVariant variant;

  /// Overrides the accent for this button only. Prefer the theme default.
  final Color? color;
  final bool isLoading;

  /// Stretch to the full available width.
  final bool expand;

  /// Read by screen readers instead of the child's text when provided.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Keep the enabled look while loading so the spinner stays legible;
    // taps are swallowed below.
    final effectiveOnPressed = isLoading && onPressed != null
        ? () {}
        : onPressed;

    final content = isLoading
        ? SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: variant == TappedButtonVariant.filled
                  ? theme.colorScheme.onPrimary
                  : color ?? theme.colorScheme.primary,
            ),
          )
        : child;

    final button = switch (variant) {
      TappedButtonVariant.filled => FilledButton(
        onPressed: effectiveOnPressed,
        style: color == null
            ? null
            : FilledButton.styleFrom(backgroundColor: color),
        child: content,
      ),
      TappedButtonVariant.outline => OutlinedButton(
        onPressed: effectiveOnPressed,
        style: color == null
            ? null
            : OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color!),
              ),
        child: content,
      ),
      TappedButtonVariant.text => TextButton(
        onPressed: effectiveOnPressed,
        style: color == null
            ? null
            : TextButton.styleFrom(foregroundColor: color),
        child: content,
      ),
    };

    final sized = ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: TappedSizes.minTapTarget,
        minWidth: TappedSizes.minTapTarget,
      ),
      child: expand ? SizedBox(width: double.infinity, child: button) : button,
    );

    final interactive = isLoading ? IgnorePointer(child: sized) : sized;

    if (semanticsLabel == null) return interactive;
    return Semantics(
      label: semanticsLabel,
      button: true,
      enabled: onPressed != null && !isLoading,
      child: interactive,
    );
  }
}
