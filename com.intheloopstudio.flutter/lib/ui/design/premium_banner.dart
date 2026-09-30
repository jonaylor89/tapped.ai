import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/utils/premium_builder.dart';

class PremiumBanner extends StatelessWidget {
  const PremiumBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return PremiumBuilder(
      builder: (context, isPremium) {
        if (isPremium) {
          return const SizedBox.shrink();
        }

        return GlassBanner(
          icon: CupertinoIcons.sparkles,
          tint: const Color(0xffE91E63),
          title: 'tapped premium',
          message: 'get booked more with unlimited discovery',
          actionLabel: 'upgrade',
          onAction: () => context.push(PaywallPage()),
        );
      },
    );
  }
}
