import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass_pressable.dart';
import 'package:intheloopapp/ui/design/glass/glass_tokens.dart';
import 'package:intheloopapp/ui/design/glass/liquid_glass.dart';

/// Content card on a glass slab. Tappable cards get press feedback.
class GlassCard extends StatelessWidget {
  const GlassCard({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.all(TappedSpacing.lg),
    this.margin,
    this.variant = GlassVariant.regular,
    this.tint,
    this.borderRadius,
    this.semanticsLabel,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final GlassVariant variant;
  final Color? tint;
  final BorderRadius? borderRadius;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final card = LiquidGlass(
      variant: variant,
      tint: tint,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius ?? GlassRadius.cardAll,
      ),
      padding: padding,
      child: child,
    );

    final body = (onTap == null && onLongPress == null)
        ? card
        : GlassPressable(
            onPressed: onTap,
            onLongPress: onLongPress,
            semanticsLabel: semanticsLabel,
            child: card,
          );

    if (margin == null) return body;
    return Padding(padding: margin!, child: body);
  }
}

/// A large image card with content overlaid on a glass strip along the
/// bottom — the pattern for venues, gigs and bookings.
class GlassImageCard extends StatelessWidget {
  const GlassImageCard({
    required this.image,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.height = 220,
    this.width,
    this.topRight,
    this.topLeft,
    this.borderRadius,
    this.semanticsLabel,
    this.heroTag,
    super.key,
  });

  final ImageProvider image;

  /// When set, the image participates in a [Hero] transition.
  final Object? heroTag;
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double height;
  final double? width;

  /// Floating pill in the top-right corner (e.g. distance, price).
  final Widget? topRight;
  final Widget? topLeft;
  final BorderRadius? borderRadius;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? GlassRadius.cardAll;
    final content = ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        height: height,
        width: width ?? double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (heroTag != null)
              Hero(
                tag: heroTag!,
                child: Image(image: image, fit: BoxFit.cover),
              )
            else
              Image(image: image, fit: BoxFit.cover),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.05),
                    Colors.black.withValues(alpha: 0.0),
                    Colors.black.withValues(alpha: 0.35),
                  ],
                  stops: const [0, 0.5, 1],
                ),
              ),
            ),
            if (topLeft != null)
              Positioned(
                top: TappedSpacing.md,
                left: TappedSpacing.md,
                child: topLeft!,
              ),
            if (topRight != null)
              Positioned(
                top: TappedSpacing.md,
                right: TappedSpacing.md,
                child: topRight!,
              ),
            Positioned(
              left: TappedSpacing.sm,
              right: TappedSpacing.sm,
              bottom: TappedSpacing.sm,
              child: LiquidGlass(
                variant: GlassVariant.regular,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    (radius.topLeft.x - TappedSpacing.sm).clamp(8, 40),
                  ),
                ),
                shadow: false,
                padding: const EdgeInsets.symmetric(
                  horizontal: TappedSpacing.lg,
                  vertical: TappedSpacing.md,
                ),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );

    if (onTap == null && onLongPress == null) return content;
    return GlassPressable(
      onPressed: onTap,
      onLongPress: onLongPress,
      semanticsLabel: semanticsLabel,
      child: content,
    );
  }
}
