import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';

class DownForMainenanceView extends StatelessWidget {
  const DownForMainenanceView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassAmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: GlassMetrics.edgeInset + TappedSpacing.xs,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: LiquidGlass(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(GlassRadius.card),
                    ),
                    padding: const EdgeInsets.all(TappedSpacing.md),
                    child: Image.asset('assets/icon_512.png', width: 96),
                  ),
                ),
                const SizedBox(height: TappedSpacing.xxl),
                Text(
                  "we're doing some\nmaintenance",
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: TappedSpacing.md),
                Text(
                  "tapped will be back shortly — thanks for your patience",
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
