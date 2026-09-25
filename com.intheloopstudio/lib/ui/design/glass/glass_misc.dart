import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass_button.dart';
import 'package:intheloopapp/ui/design/glass/glass_pressable.dart';
import 'package:intheloopapp/ui/design/glass/glass_tokens.dart';
import 'package:intheloopapp/ui/design/glass/liquid_glass.dart';

/// Capsule search field on glass. Either a real text field or, with
/// [onTap] and `readOnly`, a tappable trigger that opens a search screen.
class GlassSearchField extends StatelessWidget {
  const GlassSearchField({
    this.controller,
    this.focusNode,
    this.hintText = 'search',
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.readOnly = false,
    this.autofocus = false,
    this.trailing,
    this.variant = GlassVariant.regular,
    super.key,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final bool readOnly;
  final bool autofocus;
  final Widget? trailing;
  final GlassVariant variant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.5);

    final field = LiquidGlass.capsule(
      variant: variant,
      height: GlassMetrics.control,
      padding: const EdgeInsets.only(
        left: TappedSpacing.lg,
        right: TappedSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(CupertinoIcons.search, size: 18, color: muted),
          const SizedBox(width: TappedSpacing.sm),
          Expanded(
            child: readOnly
                ? Text(
                    controller?.text.isNotEmpty ?? false
                        ? controller!.text
                        : hintText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: controller?.text.isNotEmpty ?? false
                          ? theme.colorScheme.onSurface
                          : muted,
                    ),
                  )
                : TextField(
                    controller: controller,
                    focusNode: focusNode,
                    autofocus: autofocus,
                    onChanged: onChanged,
                    onSubmitted: onSubmitted,
                    textInputAction: TextInputAction.search,
                    style: theme.textTheme.bodyLarge,
                    cursorColor: theme.colorScheme.primary,
                    decoration: InputDecoration(
                      hintText: hintText,
                      hintStyle: theme.textTheme.bodyLarge?.copyWith(
                        color: muted,
                      ),
                      filled: false,
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );

    if (!readOnly || onTap == null) return field;
    return GlassPressable(onPressed: onTap, haptics: false, child: field);
  }
}

/// Inline notice: icon, message and an optional action. Used for premium
/// upsells, task nudges and inline errors.
class GlassBanner extends StatelessWidget {
  const GlassBanner({
    required this.message,
    this.icon,
    this.title,
    this.actionLabel,
    this.onAction,
    this.tint,
    this.margin = const EdgeInsets.symmetric(vertical: TappedSpacing.sm),
    super.key,
  });

  final String message;
  final String? title;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? tint;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = tint != null
        ? Colors.white
        : theme.colorScheme.onSurface;

    final body = LiquidGlass(
      tint: tint,
      shape: RoundedRectangleBorder(borderRadius: GlassRadius.controlAll),
      padding: const EdgeInsets.fromLTRB(
        TappedSpacing.lg,
        TappedSpacing.md,
        TappedSpacing.sm,
        TappedSpacing.md,
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: foreground, size: 22),
            const SizedBox(width: TappedSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Text(
                    title!,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: foreground.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(width: TappedSpacing.sm),
            GlassButton(
              label: actionLabel!,
              compact: true,
              onPressed: onAction,
            ),
          ],
        ],
      ),
    );

    final tappable = onAction != null && actionLabel == null
        ? GlassPressable(onPressed: onAction, child: body)
        : body;

    return Padding(padding: margin, child: tappable);
  }
}

/// Centered empty / error state with an SF-style symbol.
class GlassEmptyState extends StatelessWidget {
  const GlassEmptyState({
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Smaller symbol and padding for use inside a section or card.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final symbol = compact ? 56.0 : 88.0;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(
          compact ? TappedSpacing.xl : TappedSpacing.xxxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LiquidGlass.circle(
              width: symbol,
              height: symbol,
              child: Center(
                child: Icon(
                  icon,
                  size: compact ? 24 : 38,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
            SizedBox(height: compact ? TappedSpacing.md : TappedSpacing.xl),
            Text(
              title,
              textAlign: TextAlign.center,
              style:
                  (compact
                          ? theme.textTheme.titleMedium
                          : theme.textTheme.titleLarge)
                      ?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
            ),
            if (message != null) ...[
              const SizedBox(height: TappedSpacing.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: TappedSpacing.xl),
              GlassButton.primary(label: actionLabel!, onPressed: onAction),
            ],
          ],
        ),
      ),
    );
  }
}

/// Section title used between groups of content on a page.
class GlassSectionTitle extends StatelessWidget {
  const GlassSectionTitle(
    this.title, {
    this.trailing,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(
      GlassMetrics.edgeInset,
      TappedSpacing.xl,
      GlassMetrics.edgeInset,
      TappedSpacing.md,
    ),
    super.key,
  });

  final String title;
  final Widget? trailing;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
          ),
          if (trailing != null) trailing!,
          if (actionLabel != null)
            GlassPressable(
              onPressed: onAction,
              haptics: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TappedSpacing.xs,
                  vertical: TappedSpacing.xs,
                ),
                child: Text(
                  actionLabel!,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Native-feeling progress indicator centred in its parent.
class GlassLoading extends StatelessWidget {
  const GlassLoading({this.radius = 14, super.key});

  final double radius;

  @override
  Widget build(BuildContext context) {
    return Center(child: CupertinoActivityIndicator(radius: radius));
  }
}

/// Text input on glass for forms. Label sits above the field like a grouped
/// iOS form; errors render beneath in red.
class GlassTextField extends StatelessWidget {
  const GlassTextField({
    this.controller,
    this.label,
    this.hintText,
    this.errorText,
    this.helperText,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.autocorrect = true,
    this.autofocus = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.prefixIcon,
    this.suffix,
    this.initialValue,
    this.readOnly = false,
    this.onTap,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.focusNode,
    this.enabled = true,
    this.validator,
    super.key,
  });

  final TextEditingController? controller;
  final String? label;
  final FormFieldValidator<String>? validator;
  final String? hintText;
  final String? errorText;
  final String? helperText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final bool autocorrect;
  final bool autofocus;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final IconData? prefixIcon;
  final Widget? suffix;
  final String? initialValue;
  final bool readOnly;
  final VoidCallback? onTap;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final FocusNode? focusNode;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.5);
    final hasError = errorText != null && errorText!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(
              left: TappedSpacing.lg,
              bottom: TappedSpacing.sm,
            ),
            child: Text(
              label!.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: muted,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        LiquidGlass(
          shape: RoundedRectangleBorder(
            borderRadius: GlassRadius.controlAll,
            side: hasError
                ? const BorderSide(color: TappedColors.error)
                : BorderSide.none,
          ),
          shadow: false,
          padding: EdgeInsets.symmetric(
            horizontal: TappedSpacing.lg,
            vertical: (maxLines ?? 1) > 1 ? TappedSpacing.md : 0,
          ),
          child: TextFormField(
            controller: controller,
            focusNode: focusNode,
            initialValue: controller == null ? initialValue : null,
            enabled: enabled,
            readOnly: readOnly,
            onTap: onTap,
            autofocus: autofocus,
            onChanged: onChanged,
            onFieldSubmitted: onSubmitted,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            obscureText: obscureText,
            autocorrect: autocorrect,
            maxLines: maxLines,
            minLines: minLines,
            maxLength: maxLength,
            textCapitalization: textCapitalization,
            inputFormatters: inputFormatters,
            validator: validator,
            cursorColor: theme.colorScheme.primary,
            style: theme.textTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: theme.textTheme.bodyLarge?.copyWith(color: muted),
              filled: false,
              counterText: '',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              prefixIcon: prefixIcon == null
                  ? null
                  : Icon(prefixIcon, size: 20, color: muted),
              prefixIconConstraints: const BoxConstraints(minWidth: 32),
              suffixIcon: suffix,
              contentPadding: EdgeInsets.symmetric(
                vertical: (maxLines ?? 1) > 1 ? 0 : 15,
              ),
            ),
          ),
        ),
        if (hasError || helperText != null)
          Padding(
            padding: const EdgeInsets.only(
              left: TappedSpacing.lg,
              top: TappedSpacing.xs + 2,
            ),
            child: Text(
              hasError ? errorText! : helperText!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: hasError ? TappedColors.error : muted,
              ),
            ),
          ),
      ],
    );
  }
}

/// Layout for one step of a [TappedForm]-style questionnaire: a large
/// conversational title, optional caption, and the input below.
class GlassQuestion extends StatelessWidget {
  const GlassQuestion({
    required this.title,
    required this.child,
    this.caption,
    super.key,
  });

  final String title;
  final String? caption;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: GlassMetrics.edgeInset),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: TappedSpacing.xs),
            Text(
              caption!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
          const SizedBox(height: TappedSpacing.xl),
          child,
        ],
      ),
    );
  }
}
