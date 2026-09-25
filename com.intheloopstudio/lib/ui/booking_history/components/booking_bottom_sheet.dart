import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/booking_history/booking_history_cubit.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/profile/components/booking_card.dart';
import 'package:intheloopapp/ui/profile/components/booking_tile.dart';
import 'package:intheloopapp/utils/current_user_builder.dart';

/// Glass sheet that floats over the booking map; snaps between a peek
/// strip, half, and full height.
class BookingBottomSheet extends StatelessWidget {
  const BookingBottomSheet({
    required this.user,
    super.key,
  });

  final UserModel user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CurrentUserBuilder(
      builder: (context, currentUser) {
        return BlocBuilder<BookingHistoryCubit, BookingHistoryState>(
          builder: (context, state) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.12,
              minChildSize: 0.12,
              maxChildSize: 0.94,
              snap: true,
              snapSizes: const [0.12, 0.5, 0.94],
              builder: (context, scrollController) => LiquidGlass(
                variant: GlassVariant.prominent,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(GlassRadius.sheet),
                  ),
                ),
                child: CustomScrollView(
                  controller: scrollController,
                  physics: const ClampingScrollPhysics(),
                  slivers: [
                    const SliverToBoxAdapter(child: GlassGrabber()),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: GlassMetrics.edgeInset,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'bookings',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '${state.bookings.length} '
                                    '${state.bookings.length == 1 ? 'gig' : 'gigs'}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.55),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            GlassIconButton(
                              icon: state.gridView
                                  ? CupertinoIcons.list_bullet
                                  : CupertinoIcons.square_grid_2x2,
                              size: 38,
                              iconSize: 18,
                              semanticsLabel: state.gridView
                                  ? 'show list'
                                  : 'show grid',
                              onPressed: () => context
                                  .read<BookingHistoryCubit>()
                                  .toggleGridView(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (currentUser.id == user.id)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: GlassMetrics.edgeInset,
                            vertical: TappedSpacing.md,
                          ),
                          child: GlassButton(
                            label: 'add past booking',
                            icon: CupertinoIcons.add,
                            expand: true,
                            onPressed: () => context.push(AddPastBookingPage()),
                          ),
                        ),
                      ),
                    if (state.bookings.isEmpty)
                      const SliverToBoxAdapter(
                        child: GlassEmptyState(
                          icon: CupertinoIcons.calendar,
                          title: 'no bookings yet',
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: GlassMetrics.edgeInset,
                          vertical: TappedSpacing.sm,
                        ),
                        sliver: state.gridView
                            ? SliverGrid.count(
                                crossAxisCount: 2,
                                crossAxisSpacing: TappedSpacing.md,
                                mainAxisSpacing: TappedSpacing.md,
                                childAspectRatio: 0.78,
                                children: state.bookings.map((booking) {
                                  return BookingCard(
                                    visitedUser: user,
                                    booking: booking,
                                  );
                                }).toList(),
                              )
                            : SliverList.builder(
                                itemCount: state.bookings.length,
                                itemBuilder: (context, index) {
                                  return BookingTile(
                                    visitedUser: user,
                                    booking: state.bookings[index],
                                  );
                                },
                              ),
                      ),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: GlassMetrics.bottomBarClearance),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
