import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/domains/models/social_following.dart';
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/profile/components/message_button.dart';
import 'package:intheloopapp/ui/profile/components/request_to_book.dart';
import 'package:intheloopapp/ui/profile/components/request_to_perform.dart';
import 'package:intheloopapp/ui/profile/components/settings_button.dart';
import 'package:intheloopapp/ui/profile/components/share_button.dart';
import 'package:intheloopapp/ui/profile/profile_cubit.dart';
import 'package:intl/intl.dart';

/// Stats strip + primary actions directly under the hero.
class HeaderSliver extends StatelessWidget {
  const HeaderSliver({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        final user = state.visitedUser;
        final isCurrentUser = state.currentUser.id == user.id;
        final performerReviews =
            user.performerInfo.toNullable()?.reviewCount ?? 0;
        final bookerReviews = user.bookerInfo.toNullable()?.reviewCount ?? 0;
        final allReviewCount = performerReviews + bookerReviews;
        final compact = NumberFormat.compactCurrency(
          decimalDigits: 0,
          symbol: '',
        );
        final showFollowers =
            user.socialFollowing.audienceSize > 0 || isCurrentUser;

        return Padding(
          padding: const EdgeInsets.fromLTRB(
            GlassMetrics.edgeInset,
            TappedSpacing.md,
            GlassMetrics.edgeInset,
            0,
          ),
          child: Column(
            children: [
              if (allReviewCount > 0)
                GlassCard(
                  padding: const EdgeInsets.symmetric(
                    vertical: TappedSpacing.md,
                  ),
                  child: Row(
                    children: [
                      if (showFollowers)
                        _Stat(
                          value: compact.format(
                            user.socialFollowing.audienceSize,
                          ),
                          label: 'followers',
                          onTap: isCurrentUser
                              ? () => context.push(SettingsPage())
                              : null,
                        ),
                      _Stat(
                        value: compact.format(allReviewCount),
                        label: allReviewCount == 1 ? 'review' : 'reviews',
                        onTap: () => context.push(
                          ReviewsPage(userId: user.id),
                        ),
                      ),
                      _Stat(
                        value: switch (user.overallRating) {
                          None() => '–',
                          Some(:final value) => value.toStringAsFixed(1),
                        },
                        label: 'rating',
                        icon: CupertinoIcons.star_fill,
                      ),
                    ],
                  ),
                ),
              if (allReviewCount > 0) const SizedBox(height: TappedSpacing.md),
              if (isCurrentUser)
                const Row(
                  children: [
                    Expanded(child: SettingsButton()),
                    SizedBox(width: TappedSpacing.sm),
                    Expanded(child: ShareButton()),
                  ],
                ),
              if (!isCurrentUser && !user.unclaimed) const MessageButton(),
              if (!isCurrentUser && user.unclaimed)
                RequestToPerform(venue: user),
              if (!isCurrentUser && state.services.isNotEmpty) ...[
                const SizedBox(height: TappedSpacing.sm),
                RequestToBookButton(user: user),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    this.icon,
    this.onTap,
  });

  final String value;
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: GlassPressable(
        onPressed: onTap,
        semanticsLabel: '$value $label',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: Colors.amber),
                  const SizedBox(width: 4),
                ],
                Text(
                  value,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
