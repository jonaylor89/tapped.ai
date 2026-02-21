import 'package:flutter/material.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
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

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: TappedSpacing.sm),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: TappedRadius.lgAll,
              gradient: const LinearGradient(
                colors: [
                  Color(0xCCB71C1C),
                  Color(0xCCE91E63),
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(TappedSpacing.sm),
              child: Row(
                children: [
                  const Icon(
                    Icons.star,
                    color: TappedColors.textOnImage,
                  ),
                  const SizedBox(width: TappedSpacing.sm),
                  const Expanded(
                    child: Text(
                      'try tapped premium to increase your chances of getting booked!',
                      style: TextStyle(
                        color: TappedColors.textOnImage,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      context.push(PaywallPage());
                    },
                    child: const Text(
                      'upgrade',
                      style: TextStyle(
                        color: TappedColors.textOnImage,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
