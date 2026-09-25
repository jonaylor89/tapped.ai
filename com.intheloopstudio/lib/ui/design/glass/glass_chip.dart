import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass_pressable.dart';
import 'package:intheloopapp/ui/design/glass/glass_tokens.dart';
import 'package:intheloopapp/ui/design/glass/liquid_glass.dart';

/// Capsule filter chip. Selected chips fill with the accent.
class GlassChip extends StatelessWidget {
  const GlassChip({
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
    this.tint,
    this.count,
    this.variant = GlassVariant.regular,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color? tint;
  final int? count;
  final GlassVariant variant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fill = selected ? (tint ?? scheme.primary) : null;
    final foreground = selected ? Colors.white : scheme.onSurface;

    final chip = LiquidGlass.capsule(
      tint: fill,
      variant: variant,
      shadow: false,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: TappedSpacing.md),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: foreground),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 6),
            Text(
              '$count',
              style: theme.textTheme.labelSmall?.copyWith(
                color: foreground.withValues(alpha: 0.7),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (selected && onTap != null) ...[
            const SizedBox(width: 4),
            Icon(CupertinoIcons.xmark, size: 12, color: foreground),
          ],
        ],
      ),
    );

    if (onTap == null) return chip;
    return GlassPressable(onPressed: onTap, child: chip);
  }
}

/// Small, non-interactive status pill (e.g. "confirmed", "3 mi").
class GlassPill extends StatelessWidget {
  const GlassPill({
    required this.label,
    this.icon,
    this.tint,
    this.foreground,
    this.variant = GlassVariant.regular,
    super.key,
  });

  final String label;
  final IconData? icon;
  final Color? tint;
  final Color? foreground;
  final GlassVariant variant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg =
        foreground ??
        (tint != null ? Colors.white : theme.colorScheme.onSurface);
    return LiquidGlass.capsule(
      tint: tint,
      variant: variant,
      shadow: false,
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: TappedSpacing.sm + 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// One option in a [GlassSegmentedControl].
class GlassSegment {
  const GlassSegment({required this.label, this.icon});

  final String label;
  final IconData? icon;
}

/// Sliding-pill segmented control on glass, like `UISegmentedControl`.
class GlassSegmentedControl<T> extends StatelessWidget {
  const GlassSegmentedControl({
    required this.segments,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  /// Convenience for text-only segments.
  GlassSegmentedControl.labels({
    required Map<T, String> labels,
    required this.selected,
    required this.onChanged,
    super.key,
  }) : segments = {
         for (final e in labels.entries) e.key: GlassSegment(label: e.value),
       };

  final Map<T, GlassSegment> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keys = segments.keys.toList();
    final index = keys.indexOf(selected).clamp(0, keys.length - 1);

    return LiquidGlass.capsule(
      shadow: false,
      height: 40,
      padding: const EdgeInsets.all(3),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segW = constraints.maxWidth / keys.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: GlassMotion.release,
                curve: GlassMotion.spring,
                left: segW * index,
                top: 0,
                bottom: 0,
                width: segW,
                child: LiquidGlass.capsule(
                  tint: theme.colorScheme.primary,
                  shadow: false,
                  child: const SizedBox.expand(),
                ),
              ),
              Row(
                children: [
                  for (final k in keys)
                    Expanded(
                      child: GlassPressable(
                        onPressed: () => onChanged(k),
                        semanticsLabel: segments[k]!.label,
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: GlassMotion.reveal,
                            style: theme.textTheme.labelLarge!.copyWith(
                              fontWeight: FontWeight.w600,
                              color: k == selected
                                  ? Colors.white
                                  : theme.colorScheme.onSurface,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (segments[k]!.icon != null) ...[
                                  Icon(
                                    segments[k]!.icon,
                                    size: 15,
                                    color: k == selected
                                        ? Colors.white
                                        : theme.colorScheme.onSurface,
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Text(segments[k]!.label),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
