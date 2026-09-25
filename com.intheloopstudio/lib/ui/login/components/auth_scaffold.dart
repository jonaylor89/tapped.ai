import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shared chrome for the auth screens: ambient background, floating back
/// and info controls, a large conversational title and a keyboard-aware
/// scrolling body.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    required this.title,
    required this.children,
    this.subtitle,
    this.footer,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topPad = MediaQuery.paddingOf(context).top;
    return GlassAmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                GlassMetrics.edgeInset + TappedSpacing.xs,
                topPad + GlassMetrics.iconControl + TappedSpacing.xxl,
                GlassMetrics.edgeInset + TappedSpacing.xs,
                TappedSpacing.xxxl,
              ),
              children: [
                Text(
                  title,
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: TappedSpacing.sm),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
                const SizedBox(height: TappedSpacing.xxl),
                ...children,
                if (footer != null) ...[
                  const SizedBox(height: TappedSpacing.xl),
                  footer!,
                ],
              ],
            ),
            Positioned(
              top: topPad + TappedSpacing.sm,
              left: GlassMetrics.edgeInset,
              right: GlassMetrics.edgeInset,
              child: Row(
                children: [
                  if (Navigator.of(context).canPop())
                    GlassIconButton(
                      icon: CupertinoIcons.chevron_back,
                      semanticsLabel: 'back',
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  const Spacer(),
                  GlassIconButton(
                    icon: CupertinoIcons.info,
                    semanticsLabel: 'about tapped',
                    onPressed: () => launchUrl(Uri.parse('https://tapped.ai')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "── or ──" divider used between credential and social sign-in.
class AuthDivider extends StatelessWidget {
  const AuthDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurface.withValues(alpha: 0.35);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: TappedSpacing.xl),
      child: Row(
        children: [
          Expanded(child: Divider(height: 0, thickness: 0.5, color: color)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: TappedSpacing.md),
            child: Text(
              'or',
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
          Expanded(child: Divider(height: 0, thickness: 0.5, color: color)),
        ],
      ),
    );
  }
}

void showAuthError(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: TappedColors.error,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GlassRadius.control),
        ),
        content: Text(message),
      ),
    );
}
