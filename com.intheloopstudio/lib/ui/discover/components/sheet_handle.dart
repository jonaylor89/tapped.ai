import 'package:flutter/material.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/discover/discover_cubit.dart';
import 'package:intheloopapp/ui/user_avatar.dart';

class SheetHandle extends StatelessWidget {
  const SheetHandle({
    required this.currentUser,
    required this.state,
    super.key,
  });

  final UserModel currentUser;
  final DiscoverState state;

  String _countLabel() {
    return switch (state.mapOverlay) {
      MapOverlay.venues => () {
          final n = state.venueHits.length;
          return '$n${n >= 75 ? '+' : ''} ${n == 1 ? 'venue' : 'venues'}';
        }(),
      MapOverlay.opportunities => () {
          final n = state.opportunityHits.length;
          return '$n${n >= 75 ? '+' : ''} ${n == 1 ? 'gig' : 'gigs'}';
        }(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: TappedSpacing.md),
            child: Container(
              height: 4,
              width: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: theme.colorScheme.onSurface.withOpacity(0.15),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(
            bottom: TappedSpacing.xxl,
            left: TappedSpacing.xl,
            right: TappedSpacing.xl,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 35),
              Text(
                _countLabel(),
                style: TappedTypography.bodyLg.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Container(
                height: 35,
                width: 35,
                padding: const EdgeInsets.all(1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: UserAvatar(
                  radius: 45,
                  imageUrl: currentUser.profilePicture,
                  pushUser: Option.of(currentUser),
                  pushId: Option.of(currentUser.id),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
