import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intheloopapp/domains/authentication_bloc/authentication_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/discover/discover_view.dart';
import 'package:intheloopapp/ui/premium_theme_cubit.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:intheloopapp/utils/current_user_builder.dart';
import 'package:intheloopapp/utils/premium_builder.dart';

class ShellView extends StatelessWidget {
  const ShellView({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return CurrentUserBuilder(
      builder: (context, currentUser) {
        return PremiumBuilder(
          builder: (context, isPremium) {
            context
                .read<PremiumThemeCubit>()
                .updateTheme(isPremiumMode: isPremium);
            return BlocBuilder<NavigationBloc, NavigationState>(
              builder: (context, state) {
                if (isPremium) return const DiscoverView();
                return const _PremiumGate();
              },
            );
          },
        );
      },
    );
  }
}

/// Discover sits frosted behind a glass card that explains the value and
/// offers the trial — the map is still visibly alive underneath.
class _PremiumGate extends StatelessWidget {
  const _PremiumGate();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: const IgnorePointer(child: DiscoverView()),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  theme.colorScheme.surface.withValues(alpha: 0.2),
                  theme.colorScheme.surface.withValues(alpha: 0.7),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(GlassMetrics.edgeInset),
                child: GlassCard(
                  variant: GlassVariant.prominent,
                  padding: const EdgeInsets.all(TappedSpacing.xxl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: LiquidGlass.circle(
                          tint: theme.colorScheme.primary,
                          width: 72,
                          height: 72,
                          child: const Center(
                            child: Icon(
                              CupertinoIcons.sparkles,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: TappedSpacing.xl),
                      Text(
                        'discover every stage',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: TappedSpacing.sm),
                      Text(
                        'see the venues and gigs around you, filter by '
                        'genre and room size, and reach out directly.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color:
                              theme.colorScheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                      const SizedBox(height: TappedSpacing.xxl),
                      GlassButton.primary(
                        label: 'start free trial',
                        expand: true,
                        onPressed: () => context.push(PaywallPage()),
                      ),
                      const SizedBox(height: TappedSpacing.sm),
                      GlassButton.plain(
                        label: 'sign into a different account',
                        expand: true,
                        onPressed: () =>
                            context.authentication.add(LoggedOut()),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
