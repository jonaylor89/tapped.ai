import 'package:flutter/material.dart';

/// Ambient backdrop that gives Liquid Glass something to refract.
///
/// Plain flat colour behind glass reads as "grey rectangle"; a couple of
/// soft accent-coloured blooms in the corners make the blur, tint and rim
/// visible without competing with content. Very subtle in light mode, a
/// little deeper in dark mode.
class GlassAmbientBackground extends StatelessWidget {
  const GlassAmbientBackground({
    this.child,
    this.accent,
    super.key,
  });

  final Widget? child;

  /// Overrides the theme primary as the bloom colour.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = accent ?? theme.colorScheme.primary;
    final background = theme.scaffoldBackgroundColor;

    return DecoratedBox(
      decoration: BoxDecoration(color: background),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -120,
            right: -80,
            child: _Bloom(
              color: primary.withValues(alpha: isDark ? 0.28 : 0.16),
              size: 360,
            ),
          ),
          Positioned(
            bottom: -160,
            left: -120,
            child: _Bloom(
              color: (isDark ? const Color(0xFF7C4DFF) : const Color(0xFFB388FF))
                  .withValues(alpha: isDark ? 0.18 : 0.14),
              size: 420,
            ),
          ),
          Positioned(
            top: 280,
            left: -60,
            child: _Bloom(
              color: primary.withValues(alpha: isDark ? 0.10 : 0.08),
              size: 260,
            ),
          ),
          if (child != null) child!,
        ],
      ),
    );
  }
}

class _Bloom extends StatelessWidget {
  const _Bloom({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
