import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/discover/components/sheet_featured_gigs.dart';
import 'package:intheloopapp/ui/discover/components/sheet_genre_chips.dart';
import 'package:intheloopapp/ui/discover/components/sheet_handle.dart';
import 'package:intheloopapp/ui/discover/components/sheet_quick_actions.dart';
import 'package:intheloopapp/ui/discover/components/sheet_results_section.dart';
import 'package:intheloopapp/ui/discover/components/sheet_top_performers.dart';
import 'package:intheloopapp/ui/discover/components/venue_fit_utils.dart';
import 'package:intheloopapp/ui/discover/discover_cubit.dart';
import 'package:intheloopapp/ui/profile/components/feedback_button.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:intheloopapp/utils/current_user_builder.dart';
import 'package:intheloopapp/utils/premium_builder.dart';

class DraggableSheet extends StatelessWidget {
  DraggableSheet({
    DraggableScrollableController? dragController,
    super.key,
  }) : dragController = dragController ?? DraggableScrollableController();

  final DraggableScrollableController dragController;

  @override
  Widget build(BuildContext context) {
    final database = context.database;
    final theme = Theme.of(context);
    return CurrentUserBuilder(
      builder: (context, currentUser) {
        return PremiumBuilder(
          builder: (context, isPremium) {
            return FutureBuilder(
              future: database.getFeaturedOpportunities(),
              builder: (context, snapshot) {
                final featuredOpportunities = snapshot.data ?? [];
                return BlocBuilder<DiscoverCubit, DiscoverState>(
                  builder: (context, state) {
                    final sortedVenueHits =
                        sortVenuesByFit(currentUser, state.venueHits);
                    final topPerformerIds = sortedVenueHits
                        .expand((v) {
                          return v.venueInfo.fold(
                            () => <String>[],
                            (t) => t.topPerformerIds,
                          );
                        })
                        .toSet()
                        .toList();
                    return FutureBuilder(
                      future: (() async {
                        final performers = (await Future.wait(
                          topPerformerIds.map(database.getUserById),
                        ))
                            .whereType<Some<UserModel>>()
                            .map((e) => e.value)
                            .toList();

                        return performers;
                      })(),
                      builder: (context, snapshot) {
                        final performers = snapshot.data ?? [];
                        return DraggableScrollableSheet(
                          expand: false,
                          initialChildSize: 0.11,
                          minChildSize: 0.11,
                          snap: true,
                          snapSizes: const [0.11, 0.5, 1],
                          controller: dragController,
                          builder: (ctx, scrollController) => DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(TappedRadius.md),
                              ),
                              color: theme.colorScheme.surface,
                            ),
                            child: Column(
                              children: [
                                Expanded(
                                  child: SingleChildScrollView(
                                    controller: scrollController,
                                    physics: const ClampingScrollPhysics(),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        SheetHandle(
                                          currentUser: currentUser,
                                          state: state,
                                        ),
                                        const SheetQuickActions(),
                                        SheetResultsSection(
                                          currentUser: currentUser,
                                          state: state,
                                          sortedVenueHits: sortedVenueHits,
                                        ),
                                        SheetGenreChips(
                                          genreCounts: state.genreCounts,
                                        ),
                                        SheetTopPerformers(
                                          performers: performers,
                                          isPremium: isPremium,
                                        ),
                                        SheetFeaturedGigs(
                                          opportunities:
                                              featuredOpportunities,
                                        ),
                                        const SizedBox(
                                          height: TappedSpacing.md,
                                        ),
                                        const Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: TappedSpacing.lg,
                                            horizontal: TappedSpacing.xl,
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: FeedbackButton(),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 50),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
