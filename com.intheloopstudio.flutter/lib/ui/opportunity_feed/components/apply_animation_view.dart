import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/loading/logo_wave.dart';
import 'package:intheloopapp/utils/premium_builder.dart';

class ApplyAnimationView extends StatelessWidget {
  const ApplyAnimationView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassAmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(TappedSpacing.xxxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const LogoWave(height: 100, width: 100),
                const SizedBox(height: TappedSpacing.xl),
                Text(
                  'application sent',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: TappedSpacing.sm),
                PremiumBuilder(
                  builder: (context, claim) {
                    return Text(
                      switch (claim) {
                        false =>
                          'we just received your application, thanks for applying',
                        true =>
                          "adding your application to the top of the promoter's list as a premium member",
                      },
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
