import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intheloopapp/domains/bookings_bloc/bookings_bloc.dart';
import 'package:intheloopapp/domains/models/booking.dart';
import 'package:intheloopapp/ui/bookings/components/bookings_list.dart';
import 'package:intheloopapp/ui/common/opportunity_card.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/discover/components/venue_card.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:intheloopapp/utils/current_user_builder.dart';
import 'package:intheloopapp/utils/premium_builder.dart';

/// The signed-in user's booking inbox, as an inset grouped glass list.
class BookingControlsSliver extends StatelessWidget {
  const BookingControlsSliver({super.key});

  void _showBookings(
    BuildContext context, {
    required String title,
    required List<Booking> bookings,
  }) {
    showGlassSheet<void>(
      context: context,
      title: title,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: BookingsList(bookings: bookings),
      ),
    );
  }

  void _showGigsApplied(BuildContext context, String currentUserId) {
    final database = context.database;
    showGlassSheet<void>(
      context: context,
      title: 'gigs applied',
      builder: (context) => SizedBox(
        height: 300,
        child: FutureBuilder(
          future: database.getAppliedOpportunitiesByUserId(currentUserId),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const GlassLoading();
            final ops = snapshot.data ?? [];
            if (ops.isEmpty) {
              return const GlassEmptyState(
                icon: CupertinoIcons.tickets,
                title: 'nothing yet',
                message: 'gigs you apply to will show up here',
              );
            }
            return ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: ops.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: TappedSpacing.sm),
              itemBuilder: (context, i) => OpportunityCard(opportunity: ops[i]),
            );
          },
        ),
      ),
    );
  }

  void _showContactedVenues(BuildContext context, String currentUserId) {
    final database = context.database;
    showGlassSheet<void>(
      context: context,
      title: 'contacted venues',
      builder: (context) => SizedBox(
        height: 260,
        child: FutureBuilder(
          future: database.getContactedVenues(currentUserId),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const GlassLoading();
            final venues = snapshot.data ?? [];
            if (venues.isEmpty) {
              return const GlassEmptyState(
                icon: CupertinoIcons.bubble_left,
                title: 'nothing yet',
                message: 'venues you reach out to will show up here',
              );
            }
            return ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: venues.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: TappedSpacing.sm),
              itemBuilder: (context, i) => VenueCard(venue: venues[i]),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BookingsBloc, BookingsState>(
      builder: (context, state) {
        final anyBookings = state.pendingBookings.isNotEmpty ||
            state.upcomingBookings.isNotEmpty ||
            state.canceledBookings.isNotEmpty;

        if (!anyBookings) {
          return const SizedBox.shrink();
        }

        return CurrentUserBuilder(
          builder: (context, currentUser) {
            return PremiumBuilder(
              builder: (context, isPremium) {
                return GlassSection(
                  header: 'bookings',
                  children: [
                    if (state.pendingBookings.isNotEmpty)
                      GlassListTile(
                        leadingIcon: CupertinoIcons.clock_fill,
                        leadingColor: Colors.orange,
                        title: 'requests',
                        trailing: GlassBadge(
                          count: state.pendingBookings.length,
                        ),
                        showChevron: true,
                        onTap: () => _showBookings(
                          context,
                          title: 'booking requests',
                          bookings: state.pendingBookings,
                        ),
                      ),
                    if (state.upcomingBookings.isNotEmpty)
                      GlassListTile(
                        leadingIcon: CupertinoIcons.calendar,
                        title: 'upcoming',
                        value: '${state.upcomingBookings.length}',
                        showChevron: true,
                        onTap: () => _showBookings(
                          context,
                          title: 'upcoming bookings',
                          bookings: state.upcomingBookings,
                        ),
                      ),
                    if (state.canceledBookings.isNotEmpty)
                      GlassListTile(
                        leadingIcon: CupertinoIcons.xmark_circle_fill,
                        leadingColor: Colors.redAccent,
                        title: 'canceled',
                        value: '${state.canceledBookings.length}',
                        showChevron: true,
                        onTap: () => _showBookings(
                          context,
                          title: 'canceled bookings',
                          bookings: state.canceledBookings,
                        ),
                      ),
                    if (isPremium)
                      GlassListTile(
                        leadingIcon: CupertinoIcons.bubble_left_fill,
                        title: 'contacted venues',
                        showChevron: true,
                        onTap: () =>
                            _showContactedVenues(context, currentUser.id),
                      ),
                    GlassListTile(
                      leadingIcon: CupertinoIcons.tickets_fill,
                      title: 'gigs applied',
                      showChevron: true,
                      onTap: () => _showGigsApplied(context, currentUser.id),
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
