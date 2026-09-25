import 'package:flutter/material.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/domains/models/review.dart';
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/user_tile.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:skeletons/skeletons.dart';

class ReviewTile extends StatelessWidget {
  const ReviewTile({
    required this.review,
    super.key,
  });

  final Review review;

  @override
  Widget build(BuildContext context) {
    final database = context.database;
    final reviewerId = switch (review) {
      PerformerReview(:final bookerId) => bookerId,
      BookerReview(:final performerId) => performerId,
    };
    final theme = Theme.of(context);
    return FutureBuilder<Option<UserModel>>(
      future: database.getUserById(reviewerId),
      builder: (context, snapshot) {
        return switch (snapshot.data) {
          null => SkeletonListTile(),
          None() => SkeletonListTile(),
          Some(:final value) => value.deleted
              ? const SizedBox.shrink()
              : GlassCard(
                  padding: const EdgeInsets.only(bottom: TappedSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      UserTile(
                        userId: value.id,
                        user: Option.of(value),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: TappedSpacing.md,
                        ),
                        child: Text(
                          review.overallReview,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        };
      },
    );
  }
}
