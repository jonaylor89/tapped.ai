import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass_pressable.dart';
import 'package:intheloopapp/ui/design/glass/glass_tokens.dart';
import 'package:intheloopapp/ui/design/glass/liquid_glass.dart';

enum GlassButtonStyle {
  /// Accent-tinted glass. One per screen — the primary action.
  primary,

  /// Neutral glass. Secondary actions.
  glass,

  /// Red-tinted glass for destructive actions.
  destructive,

  /// No surface, just a label. Tertiary actions inside sheets and lists.
  plain,
}

/// Capsule button in the Liquid Glass material.
class GlassButton extends StatelessWidget {
  const GlassButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.style = GlassButtonStyle.glass,
    this.expand = false,
    this.isLoading = false,
    this.compact = false,
    this.semanticsLabel,
    super.key,
  });

  const GlassButton.primary({
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
    this.isLoading = false,
    this.compact = false,
    this.semanticsLabel,
    super.key,
  }) : style = GlassButtonStyle.primary;

  const GlassButton.destructive({
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
    this.isLoading = false,
    this.compact = false,
    this.semanticsLabel,
    super.key,
  }) : style = GlassButtonStyle.destructive;

  const GlassButton.plain({
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
    this.isLoading = false,
    this.compact = false,
    this.semanticsLabel,
    super.key,
  }) : style = GlassButtonStyle.plain;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final GlassButtonStyle style;
  final bool expand;
  final bool isLoading;
  final bool compact;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (Color? tint, Color foreground) = switch (style) {
      GlassButtonStyle.primary => (scheme.primary, Colors.white),
      GlassButtonStyle.destructive => (TappedColors.error, Colors.white),
      GlassButtonStyle.glass => (null, scheme.onSurface),
      GlassButtonStyle.plain => (null, scheme.primary),
    };

    final textStyle = theme.textTheme.titleSmall?.copyWith(
      color: foreground,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
    );

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading)
          CupertinoActivityIndicator(color: foreground)
        else ...[
          if (icon != null) ...[
            Icon(icon, size: 18, color: foreground),
            const SizedBox(width: TappedSpacing.sm),
          ],
          Flexible(
            child: Text(
              label,
              style: textStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );

    final height = compact ? 38.0 : GlassMetrics.control;
    final padding = EdgeInsets.symmetric(
      horizontal: compact ? TappedSpacing.lg : TappedSpacing.xxl,
    );

    final Widget surface = style == GlassButtonStyle.plain
        ? SizedBox(
            height: height,
            child: Padding(padding: padding, child: content),
          )
        : LiquidGlass.capsule(
            tint: tint,
            height: height,
            padding: padding,
            variant: GlassVariant.regular,
            child: content,
          );

    return GlassPressable(
      onPressed: isLoading ? null : onPressed,
      semanticsLabel: semanticsLabel ?? label,
      child: expand ? SizedBox(width: double.infinity, child: surface) : surface,
    );
  }
}

/// 44pt circular glass control: back, close, more, share, filter.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    required this.icon,
    required this.onPressed,
    this.tint,
    this.color,
    this.size = GlassMetrics.iconControl,
    this.iconSize = 20,
    this.variant = GlassVariant.regular,
    this.badge,
    this.semanticsLabel,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color? tint;
  final Color? color;
  final double size;
  final double iconSize;
  final GlassVariant variant;

  /// Small count shown top-right (unread messages, tasks).
  final int? badge;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = color ?? (tint != null ? Colors.white : scheme.onSurface);
    final button = LiquidGlass.circle(
      tint: tint,
      variant: variant,
      width: size,
      height: size,
      child: Center(child: Icon(icon, size: iconSize, color: foreground)),
    );

    final b = badge;
    final withBadge = (b == null || b <= 0)
        ? button
        : Stack(
            clipBehavior: Clip.none,
            children: [
              button,
              Positioned(
                top: -2,
                right: -2,
                child: GlassBadge(count: b),
              ),
            ],
          );

    return GlassPressable(
      onPressed: onPressed,
      semanticsLabel: semanticsLabel,
      child: withBadge,
    );
  }
}

/// Red notification dot with a count, as on iOS app icons.
class GlassBadge extends StatelessWidget {
  const GlassBadge({required this.count, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: TappedColors.error,
        borderRadius: GlassRadius.capsuleAll,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}
