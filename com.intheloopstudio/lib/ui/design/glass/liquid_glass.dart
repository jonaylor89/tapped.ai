import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/design/glass/glass_tokens.dart';

/// How much the material lets the background through.
enum GlassVariant {
  /// Default floating chrome: readable text, background visible.
  regular,

  /// Nearly transparent; for controls sitting on imagery or maps where the
  /// content should dominate.
  clear,

  /// Opaque enough for dense text (sheets, menus, cards with paragraphs).
  prominent,
}

/// The Liquid Glass material.
///
/// Composed of four layers, bottom to top:
///  1. a backdrop blur of whatever is behind the widget,
///  2. a brightness-aware tint so foreground text stays legible,
///  3. a specular rim — a gradient hairline that is brightest where light
///     would catch the top-left edge — which is what makes it read as glass,
///  4. the child.
///
/// Pass [tint] to colour the glass: the surface stays translucent and picks
/// up a faint wash of the colour while the rim is drawn in the accent, so
/// tinted controls read as outlined glass rather than filled buttons. Pair
/// with [glassTintForeground] for legible text/icons. Use [shape] to choose
/// between a capsule, a rounded rectangle or a circle.
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    required this.child,
    this.variant = GlassVariant.regular,
    this.shape,
    this.tint,
    this.padding,
    this.blur,
    this.shadow = true,
    this.width,
    this.height,
    this.alignment,
    super.key,
  });

  /// Capsule-shaped glass (buttons, pills, search fields).
  const LiquidGlass.capsule({
    required this.child,
    this.variant = GlassVariant.regular,
    this.tint,
    this.padding,
    this.blur,
    this.shadow = true,
    this.width,
    this.height,
    this.alignment,
    super.key,
  }) : shape = const StadiumBorder();

  /// Circular glass (icon controls, avatars rings).
  const LiquidGlass.circle({
    required this.child,
    this.variant = GlassVariant.regular,
    this.tint,
    this.padding,
    this.blur,
    this.shadow = true,
    this.width,
    this.height,
    this.alignment,
    super.key,
  }) : shape = const CircleBorder();

  final Widget child;
  final GlassVariant variant;

  /// Defaults to a rounded rectangle with [GlassRadius.card].
  final ShapeBorder? shape;

  /// Optional colour cast. Alpha is applied by the material.
  final Color? tint;
  final EdgeInsetsGeometry? padding;
  final double? blur;
  final bool shadow;
  final double? width;
  final double? height;
  final AlignmentGeometry? alignment;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveShape =
        shape ?? RoundedRectangleBorder(borderRadius: GlassRadius.cardAll);
    final sigma = blur ?? _blurFor(variant);
    final fill = _fillFor(isDark: isDark);

    Widget content = child;
    if (padding != null) {
      content = Padding(padding: padding!, child: content);
    }
    if (alignment != null) {
      content = Align(alignment: alignment!, child: content);
    }

    final glass = ClipPath(
      clipper: ShapeBorderClipper(shape: effectiveShape),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: CustomPaint(
          foregroundPainter: _SpecularRimPainter(
            shape: effectiveShape,
            isDark: isDark,
            tint: tint,
          ),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              shape: effectiveShape,
              gradient: fill,
            ),
            child: content,
          ),
        ),
      ),
    );

    final sized = (width != null || height != null)
        ? SizedBox(width: width, height: height, child: glass)
        : glass;

    if (!shadow) return sized;

    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: effectiveShape,
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.10 : 0.02),
            blurRadius: 1,
            offset: const Offset(0, 0.5),
          ),
        ],
      ),
      child: sized,
    );
  }

  double _blurFor(GlassVariant v) => switch (v) {
    GlassVariant.regular => GlassBlur.regular,
    GlassVariant.clear => GlassBlur.thin,
    GlassVariant.prominent => GlassBlur.thick,
  };

  /// The tint is a diagonal gradient so the surface never looks flat: the
  /// top-left is a touch lighter (where light would land), the bottom-right a
  /// touch denser.
  Gradient _fillFor({required bool isDark}) {
    final base = isDark ? Colors.white : Colors.white;
    final shade = isDark ? Colors.black : Colors.white;

    final (double hi, double lo) = switch (variant) {
      GlassVariant.regular => isDark ? (0.14, 0.34) : (0.72, 0.52),
      GlassVariant.clear => isDark ? (0.06, 0.18) : (0.40, 0.22),
      GlassVariant.prominent => isDark ? (0.10, 0.62) : (0.90, 0.78),
    };

    final t = tint;
    if (t != null) {
      final wash = variant == GlassVariant.clear ? 0.08 : 0.14;
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(base.withValues(alpha: hi), t, wash)!,
          Color.lerp(shade.withValues(alpha: lo), t, wash + 0.06)!,
        ],
      );
    }

    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        base.withValues(alpha: hi),
        shade.withValues(alpha: lo),
      ],
    );
  }
}

/// Text/icon colour that stays legible on tinted glass: the accent itself,
/// lifted toward white in dark mode and toward black in light mode.
Color glassTintForeground(Color tint, {required bool isDark}) => Color.lerp(
  tint,
  isDark ? Colors.white : Colors.black,
  isDark ? 0.25 : 0.2,
)!;

/// A hairline that runs around the shape and fades from bright at the top
/// edge to almost nothing at the bottom — the refracted edge of a real slab
/// of glass. With a [tint], the rim becomes a 1.5pt accent outline instead.
class _SpecularRimPainter extends CustomPainter {
  const _SpecularRimPainter({
    required this.shape,
    required this.isDark,
    this.tint,
  });

  final ShapeBorder shape;
  final bool isDark;
  final Color? tint;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final t = tint;
    if (t != null) {
      final outline = shape.getOuterPath(rect.deflate(0.75));
      canvas.drawPath(
        outline,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(t, Colors.white, isDark ? 0.35 : 0.0)!,
              t.withValues(alpha: 0.85),
            ],
          ).createShader(rect),
      );
      return;
    }
    final path = shape.getOuterPath(rect.deflate(0.5));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: isDark ? 0.55 : 0.95),
          Colors.white.withValues(alpha: isDark ? 0.10 : 0.35),
          Colors.white.withValues(alpha: isDark ? 0.02 : 0.15),
        ],
        stops: const [0, 0.55, 1],
      ).createShader(rect);
    canvas.drawPath(path, paint);

    // Inner glow along the top edge: a second, softer stroke clipped so it
    // only shows at the top.
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
      ..color = Colors.white.withValues(alpha: isDark ? 0.10 : 0.35);
    canvas
      ..save()
      ..clipRect(Rect.fromLTWH(0, 0, size.width, size.height * 0.35))
      ..drawPath(path, glow)
      ..restore();
  }

  @override
  bool shouldRepaint(_SpecularRimPainter oldDelegate) =>
      oldDelegate.shape != shape ||
      oldDelegate.isDark != isDark ||
      oldDelegate.tint != tint;
}
