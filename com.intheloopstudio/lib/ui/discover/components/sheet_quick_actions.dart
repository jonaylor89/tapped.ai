import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intheloopapp/data/auth_repository.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/utils/custom_claims_builder.dart';

class SheetQuickActions extends StatelessWidget {
  const SheetQuickActions({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: TappedSpacing.xl),
          child: Row(
            children: [
              Expanded(
                child: CupertinoButton(
                  onPressed: () => context.push(GigSearchPage()),
                  borderRadius: TappedRadius.lgAll,
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  child: Text(
                    'search locations',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        CustomClaimsBuilder(
          builder: (context, claims) {
            final isAdmin = claims.contains(CustomClaim.admin);
            final isBooker = claims.contains(CustomClaim.booker);
            if (!isAdmin && !isBooker) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: TappedSpacing.xl,
              ),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  onPressed: () => context.push(AdminPage()),
                  color: TappedColors.error.withOpacity(0.1),
                  borderRadius: TappedRadius.lgAll,
                  child: const Text(
                    'add opportunity',
                    style: TextStyle(
                      color: TappedColors.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
