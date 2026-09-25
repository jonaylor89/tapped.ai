import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/profile/components/review_tile.dart';
import 'package:intheloopapp/ui/profile/profile_cubit.dart';
import 'package:intheloopapp/ui/reviews/user_reviews_feed.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';

class ReviewsSliver extends StatelessWidget {
  const ReviewsSliver({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        return switch (state.latestReview) {
          None() => const SizedBox.shrink(),
          Some(:final value) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GlassSectionTitle(
                  'reviews',
                  actionLabel: 'see all',
                  onAction: () => showCupertinoModalBottomSheet<void>(
                    context: context,
                    backgroundColor: Colors.transparent,
                    builder: (context) => UserReviewsFeed(
                      userId: state.visitedUser.id,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: GlassMetrics.edgeInset,
                  ),
                  child: ReviewTile(review: value),
                ),
              ],
            ),
        };
      },
    );
  }
}
