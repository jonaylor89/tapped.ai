import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass_pressable.dart';
import 'package:intheloopapp/ui/design/glass/glass_tokens.dart';
import 'package:intheloopapp/ui/design/glass/liquid_glass.dart';

/// Background of an inset-grouped cell group (`secondarySystemGroupedBackground`
/// on iOS). Deliberately near-opaque: on iOS, Liquid Glass is reserved for
/// floating chrome, while lists and forms stay on solid grouped cells.
class GlassGroupedSurface extends StatelessWidget {
  const GlassGroupedSurface({required this.child, this.radius = 12, super.key});

  final Widget child;
  final double radius;

  static Color fill(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF1C1C1E).withValues(alpha: 0.94)
      : Colors.white.withValues(alpha: 0.94);

  static Color separator(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? Colors.white.withValues(alpha: 0.15)
      : Colors.black.withValues(alpha: 0.12);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill(context),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: child,
      ),
    );
  }
}

/// Uppercase section header used above grouped lists and forms.
class GlassGroupHeader extends StatelessWidget {
  const GlassGroupHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        left: TappedSpacing.lg,
        right: TappedSpacing.lg,
        bottom: TappedSpacing.sm - 1,
      ),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
          letterSpacing: 0.4,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

/// Caption under a grouped list or form; red when [error].
class GlassGroupFooter extends StatelessWidget {
  const GlassGroupFooter(this.text, {this.error = false, super.key});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        left: TappedSpacing.lg,
        right: TappedSpacing.lg,
        top: TappedSpacing.sm - 1,
      ),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: error
              ? TappedColors.error
              : theme.colorScheme.onSurface.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}

/// Inset-grouped section — the iOS Settings list, rebuilt.
///
/// Rows are separated by inset hairlines; the section gets an optional
/// uppercase header and a footer caption.
class GlassSection extends StatelessWidget {
  const GlassSection({
    required this.children,
    this.header,
    this.footer,
    this.footerWidget,
    this.margin = const EdgeInsets.symmetric(
      horizontal: GlassMetrics.edgeInset,
      vertical: TappedSpacing.sm,
    ),
    this.variant = GlassVariant.regular,
    this.dividers = true,
    super.key,
  });

  final List<Widget> children;
  final String? header;
  final String? footer;
  final Widget? footerWidget;
  final EdgeInsetsGeometry margin;

  /// Kept for call-site compatibility; grouped sections always render on the
  /// solid [GlassGroupedSurface], as iOS does.
  final GlassVariant variant;
  final bool dividers;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0 && dividers) {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(left: TappedSpacing.lg),
            child: Divider(
              height: 0.5,
              thickness: 0.5,
              color: GlassGroupedSurface.separator(context),
            ),
          ),
        );
      }
      rows.add(children[i]);
    }

    return Padding(
      padding: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null) GlassGroupHeader(header!),
          GlassGroupedSurface(child: Column(children: rows)),
          if (footer != null) GlassGroupFooter(footer!),
          if (footerWidget != null)
            Padding(
              padding: const EdgeInsets.only(
                left: TappedSpacing.lg,
                right: TappedSpacing.lg,
                top: TappedSpacing.sm,
              ),
              child: footerWidget,
            ),
        ],
      ),
    );
  }
}

/// A row inside a [GlassSection]. Mirrors `UITableViewCell` styles: leading
/// icon in a coloured rounded square, title, optional subtitle/value, and a
/// disclosure chevron when tappable.
class GlassListTile extends StatelessWidget {
  const GlassListTile({
    this.title,
    this.titleWidget,
    this.subtitle,
    this.subtitleWidget,
    this.leading,
    this.leadingIcon,
    this.leadingColor,
    this.trailing,
    this.value,
    this.onTap,
    this.destructive = false,
    this.showChevron,
    this.dense = false,
    super.key,
  });

  final String? title;

  /// Custom title content; takes precedence over [title].
  final Widget? titleWidget;
  final String? subtitle;

  /// Custom subtitle content; takes precedence over [subtitle].
  final Widget? subtitleWidget;
  final Widget? leading;
  final IconData? leadingIcon;
  final Color? leadingColor;
  final Widget? trailing;

  /// Secondary text on the right (e.g. current setting value).
  final String? value;
  final VoidCallback? onTap;
  final bool destructive;
  final bool? showChevron;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = destructive ? TappedColors.error : scheme.onSurface;
    final chevron = showChevron ?? (onTap != null && trailing == null);

    Widget? lead = leading;
    if (lead == null && leadingIcon != null) {
      final c = leadingColor ?? scheme.primary;
      lead = Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(leadingIcon, size: 17, color: Colors.white),
      );
    }

    final row = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: TappedSpacing.lg,
        vertical: dense ? TappedSpacing.xs : TappedSpacing.sm + 3,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: TappedSizes.minTapTarget),
        child: Row(
          children: [
            if (lead != null) ...[
              lead,
              const SizedBox(width: TappedSpacing.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  DefaultTextStyle(
                    style: theme.textTheme.bodyLarge!.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w400,
                    ),
                    child:
                        titleWidget ??
                        Text(
                          title ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  ),
                  if (subtitle != null || subtitleWidget != null) ...[
                    const SizedBox(height: 2),
                    DefaultTextStyle(
                      style: theme.textTheme.bodySmall!.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.55),
                      ),
                      child:
                          subtitleWidget ??
                          Text(
                            subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: TappedSpacing.sm),
              Text(
                value!,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
            if (trailing != null) ...[
              const SizedBox(width: TappedSpacing.sm),
              trailing!,
            ],
            if (chevron) ...[
              const SizedBox(width: TappedSpacing.sm),
              Icon(
                CupertinoIcons.chevron_forward,
                size: 16,
                color: scheme.onSurface.withValues(alpha: 0.3),
              ),
            ],
          ],
        ),
      ),
    );

    if (onTap == null) return row;
    return GlassPressable(
      onPressed: onTap,
      haptics: false,
      scale: false,
      child: row,
    );
  }
}

/// A toggle row for [GlassSection].
class GlassSwitchTile extends StatelessWidget {
  const GlassSwitchTile({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.leadingIcon,
    this.leadingColor,
    super.key,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? leadingIcon;
  final Color? leadingColor;

  @override
  Widget build(BuildContext context) {
    return GlassListTile(
      title: title,
      subtitle: subtitle,
      leadingIcon: leadingIcon,
      leadingColor: leadingColor,
      showChevron: false,
      trailing: CupertinoSwitch(value: value, onChanged: onChanged),
    );
  }
}
