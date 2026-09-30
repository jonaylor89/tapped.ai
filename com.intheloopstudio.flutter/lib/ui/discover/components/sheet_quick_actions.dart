import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intheloopapp/data/auth_repository.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/utils/custom_claims_builder.dart';

/// Horizontal row of glass shortcuts at the top of the discover sheet.
class SheetQuickActions extends StatelessWidget {
  const SheetQuickActions({required this.currentUserId, super.key});

  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    return CustomClaimsBuilder(
      builder: (context, claims) {
        final isAdmin = claims.contains(CustomClaim.admin);
        final isBooker = claims.contains(CustomClaim.booker);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(
            horizontal: GlassMetrics.edgeInset,
          ),
          child: Row(
            children: [
              _QuickAction(
                icon: CupertinoIcons.map_fill,
                label: 'search a city',
                onPressed: () => context.push(GigSearchPage()),
              ),
              const SizedBox(width: TappedSpacing.sm),
              _QuickAction(
                icon: CupertinoIcons.calendar,
                label: 'my bookings',
                onPressed: () =>
                    context.push(BookingsPage(userId: currentUserId)),
              ),
              const SizedBox(width: TappedSpacing.sm),
              _QuickAction(
                icon: CupertinoIcons.person_crop_circle,
                label: 'settings',
                onPressed: () => context.push(SettingsPage()),
              ),
              if (isAdmin || isBooker) ...[
                const SizedBox(width: TappedSpacing.sm),
                _QuickAction(
                  icon: CupertinoIcons.plus,
                  label: 'add gig',
                  tint: TappedColors.error,
                  onPressed: () => context.push(AdminPage()),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tint,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = tint ?? theme.colorScheme.primary;
    return GlassPressable(
      onPressed: onPressed,
      semanticsLabel: label,
      child: LiquidGlass(
        shape: RoundedRectangleBorder(borderRadius: GlassRadius.controlAll),
        shadow: false,
        width: 104,
        padding: const EdgeInsets.symmetric(
          horizontal: TappedSpacing.md,
          vertical: TappedSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: fg, size: 22),
            const SizedBox(height: TappedSpacing.md),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
