import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/domains/models/genre.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/forms/location_text_field.dart';
import 'package:intheloopapp/ui/gig_search/gig_search_cubit.dart';
import 'package:intheloopapp/ui/settings/components/genre_selection.dart';
import 'package:intheloopapp/ui/user_tile.dart';
import 'package:intheloopapp/utils/app_logger.dart';
import 'package:intheloopapp/utils/current_user_builder.dart';
import 'package:intheloopapp/utils/premium_builder.dart';

/// Filter form for the "search by city" venue outreach flow.
class VenueFilterForm extends StatelessWidget {
  const VenueFilterForm({super.key});

  Future<void> _search(BuildContext context, {required bool isPremium}) {
    if (!isPremium) {
      context.push(PaywallPage());
      return Future.value();
    }

    final messenger = ScaffoldMessenger.of(context);
    return context.read<GigSearchCubit>().searchVenues().catchError(
      (Object error) {
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            content: Text(error.toString()),
          ),
        );
      },
    );
  }

  void _capacityInfo(BuildContext context) {
    showGlassSheet<void>(
      context: context,
      title: 'capacity',
      showClose: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          GlassMetrics.edgeInset,
          0,
          GlassMetrics.edgeInset,
          TappedSpacing.xl,
        ),
        child: Text(
          'the capacity range defaults to numbers that align with your '
          'previous booking history, so you reach rooms you can fill.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    return CurrentUserBuilder(
      builder: (context, currentUser) {
        return PremiumBuilder(
          builder: (context, isPremium) {
            return BlocBuilder<GigSearchCubit, GigSearchState>(
              builder: (context, state) {
                final cubit = context.read<GigSearchCubit>();
                return GlassPage(
                  title: 'find gigs',
                  subtitle: 'reach thousands of venues in seconds',
                  bottomBar: GlassBottomBar(
                    child: GlassButton.primary(
                      label: isPremium ? 'search venues' : 'unlock search',
                      icon: isPremium
                          ? CupertinoIcons.search
                          : CupertinoIcons.lock_fill,
                      expand: true,
                      onPressed: state.place.isNone() && isPremium
                          ? null
                          : () => _search(context, isPremium: isPremium),
                    ),
                  ),
                  slivers: [
                    SliverToBoxAdapter(
                      child: GlassSection(
                        header: 'who',
                        children: [
                          UserTile(
                            userId: currentUser.id,
                            user: Option.of(currentUser),
                          ),
                        ],
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: GlassMetrics.edgeInset,
                          vertical: TappedSpacing.sm,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const GlassSectionTitle(
                              'where',
                              padding: EdgeInsets.only(
                                bottom: TappedSpacing.sm,
                              ),
                            ),
                            LocationTextField(
                              initialPlace: state.place,
                              onChanged: (placeData, _) {
                                try {
                                  cubit.updateLocation(placeData);
                                } catch (e, s) {
                                  logger.e(
                                    'Error updating location',
                                    error: e,
                                    stackTrace: s,
                                  );
                                }
                              },
                            ),
                            if (state.place.isNone())
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: TappedSpacing.xs,
                                  left: TappedSpacing.sm,
                                ),
                                child: Text(
                                  'please select a city',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: TappedColors.error,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: GlassSection(
                        header: 'what',
                        children: [
                          GenreSelection(
                            standalone: false,
                            initialValue: state.genres,
                            onConfirm: (genres) {
                              cubit.updateGenres(
                                genres.whereType<Genre>().toList(),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: GlassSection(
                        header: 'capacity',
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              GlassMetrics.edgeInset,
                              TappedSpacing.md,
                              GlassMetrics.edgeInset,
                              TappedSpacing.sm,
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    GlassPill(
                                      label:
                                          '${state.capacityRangeStart} – '
                                          '${state.capacityRangeEnd == maxCapacity ? '${maxCapacity.round()}+' : state.capacityRangeEnd}',
                                    ),
                                    const Spacer(),
                                    GlassPressable(
                                      haptics: false,
                                      semanticsLabel: 'about capacity',
                                      onPressed: () => _capacityInfo(context),
                                      child: Padding(
                                        padding: const EdgeInsets.all(
                                          TappedSpacing.sm,
                                        ),
                                        child: Icon(
                                          CupertinoIcons.info_circle,
                                          size: 18,
                                          color: muted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 4,
                                    rangeThumbShape:
                                        const RoundRangeSliderThumbShape(
                                          enabledThumbRadius: 12,
                                          elevation: 2,
                                        ),
                                    overlayShape:
                                        SliderComponentShape.noOverlay,
                                  ),
                                  child: RangeSlider(
                                    values: state.capacityRange,
                                    max: maxCapacity,
                                    onChanged: cubit.updateCapacity,
                                    activeColor: theme.colorScheme.primary,
                                    inactiveColor: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.15),
                                    divisions: maxCapacity.toInt(),
                                    labels: RangeLabels(
                                      state.capacityRangeStart.toString(),
                                      state.capacityRangeEnd.toString(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: GlassMetrics.bottomBarClearance),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}
