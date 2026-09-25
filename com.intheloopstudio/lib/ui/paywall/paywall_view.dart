import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/subscription_bloc/subscription_bloc.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/loading/logo_wave.dart';
import 'package:intheloopapp/utils/app_logger.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:intheloopapp/utils/premium_builder.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:stream_chat_flutter/stream_chat_flutter.dart';

/// Premium upsell. Full-bleed hero animation behind a stack of glass
/// feature cards, with the purchase CTA floating over the bottom edge.
class PaywallView extends StatelessWidget {
  const PaywallView({
    super.key,
  });

  static const _features = [
    (
      CupertinoIcons.tickets_fill,
      'unlimited gig opportunities',
      'apply to every gig on the map, no daily cap',
    ),
    (
      CupertinoIcons.eye_fill,
      'venue intel',
      'exclusive info on venues actively looking for performers',
    ),
    (
      CupertinoIcons.envelope_fill,
      'direct contact',
      'booking emails and phone numbers for thousands of venues',
    ),
    (
      CupertinoIcons.slider_horizontal_3,
      'advanced search',
      'filter by capacity, genre, and who venues actually book',
    ),
  ];

  Future<void> _onPurchase(
    BuildContext context, {
    required Package package,
  }) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final subscriptions = context.subscriptions;
    final nav = context.nav;

    await HapticFeedback.lightImpact();
    await EasyLoading.show(
      status: 'loading...',
      maskType: EasyLoadingMaskType.black,
    );
    try {
      final purchaseResult = await Purchases.purchasePackage(
        package,
      );
      subscriptions.add(
        UpdateSubscription(
          customerInfo: purchaseResult.customerInfo,
        ),
      );

      logger.info(purchaseResult.customerInfo.toString());
    } catch (error, s) {
      logger.error('error purchasing package', error: error, stackTrace: s);
      scaffoldMessenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: TappedColors.error,
          content: const Text(
            'purchase canceled',
            style: TextStyle(color: TappedColors.textOnImage),
          ),
        ),
      );
    }

    await EasyLoading.dismiss();
    nav.pop();
  }

  Widget _alreadyPremium(BuildContext context) {
    return GlassAmbientBackground(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(TappedSpacing.xl),
          child: Column(
            children: [
              const Spacer(),
              const LogoWave(),
              const SizedBox(height: TappedSpacing.xl),
              Text(
                "you're already premium",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const Spacer(),
              GlassButton.primary(
                label: 'okay',
                expand: true,
                onPressed: () => context.pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PremiumBuilder(
      builder: (context, isPremium) {
        if (isPremium) return _alreadyPremium(context);

        return FutureBuilder(
          future: Purchases.getOfferings(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              logger.error(
                'error fetching offerings',
                error: snapshot.error,
                stackTrace: snapshot.stackTrace,
              );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: TappedColors.error,
                  content: const Text(
                    'error fetching offerings',
                    style: TextStyle(color: TappedColors.textOnImage),
                  ),
                ),
              );
            }

            final offerings = snapshot.data;

            if (offerings == null) {
              return const GlassAmbientBackground(
                child: Center(child: GlassLoading()),
              );
            }

            final offering = offerings.current;
            final packages = offering?.availablePackages ?? [];
            final package = packages.where((element) {
              return element.packageType == PackageType.monthly;
            }).first;
            final period =
                package.packageType.toString().split('.').last.toLowerCase();
            final price = package.storeProduct.price.toStringAsFixed(2);

            return Scaffold(
              backgroundColor: theme.colorScheme.surface,
              extendBodyBehindAppBar: true,
              extendBody: true,
              body: Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      'assets/splash.gif',
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0, 0.35, 0.7],
                          colors: [
                            Colors.transparent,
                            theme.colorScheme.surface.withValues(alpha: 0.7),
                            theme.colorScheme.surface,
                          ],
                        ),
                      ),
                    ),
                  ),
                  CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: MediaQuery.sizeOf(context).height * 0.34,
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: GlassMetrics.edgeInset,
                        ),
                        sliver: SliverList.list(
                          children: [
                            const GlassPill(
                              label: 'tapped premium',
                              icon: CupertinoIcons.star_fill,
                              tint: Colors.amber,
                            ),
                            const SizedBox(height: TappedSpacing.md),
                            Text(
                              'create a world tour\nfrom your iphone',
                              style: theme.textTheme.displayMedium?.copyWith(
                                fontSize: 34,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.8,
                                height: 1.05,
                              ),
                            ),
                            const SizedBox(height: TappedSpacing.xl),
                            for (final (icon, title, body) in _features) ...[
                              GlassCard(
                                padding: const EdgeInsets.all(TappedSpacing.md),
                                child: Row(
                                  children: [
                                    LiquidGlass.circle(
                                      width: 44,
                                      height: 44,
                                      tint: theme.colorScheme.primary,
                                      child: Center(
                                        child: Icon(
                                          icon,
                                          size: 20,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: TappedSpacing.md),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            title,
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            body,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color: theme.colorScheme.onSurface
                                                  .withValues(alpha: 0.6),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: TappedSpacing.sm),
                            ],
                            const SizedBox(height: 200),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    top: MediaQuery.paddingOf(context).top + TappedSpacing.sm,
                    left: GlassMetrics.edgeInset,
                    child: GlassIconButton(
                      icon: CupertinoIcons.xmark,
                      variant: GlassVariant.clear,
                      semanticsLabel: 'close',
                      onPressed: () => context.pop(),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: GlassBottomBar(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GlassButton.primary(
                            label: 'get full access · \$$price / $period',
                            expand: true,
                            onPressed: () => _onPurchase(
                              context,
                              package: package,
                            ),
                          ),
                          const SizedBox(height: TappedSpacing.sm),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              GlassButton.plain(
                                label: 'privacy',
                                compact: true,
                                onPressed: () => launchURL(
                                  context,
                                  'https://app.tapped.ai/privacy',
                                ),
                              ),
                              GlassButton.plain(
                                label: 'terms',
                                compact: true,
                                onPressed: () => launchURL(
                                  context,
                                  'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
