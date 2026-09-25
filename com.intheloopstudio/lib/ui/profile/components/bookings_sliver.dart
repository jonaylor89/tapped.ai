import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intheloopapp/domains/models/booking.dart';
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/bookings/user_bookings_feed.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/profile/components/booking_card.dart';
import 'package:intheloopapp/ui/profile/profile_cubit.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';

/// Horizontal rail of a user's most recent gigs, with an "add past gigs"
/// affordance for the signed-in user.
class BookingsSliver extends StatelessWidget {
  const BookingsSliver({super.key});

  Widget _addBookingsButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GlassMetrics.edgeInset,
        TappedSpacing.md,
        GlassMetrics.edgeInset,
        0,
      ),
      child: Column(
        children: [
          GlassButton(
            label: 'add past gigs',
            icon: CupertinoIcons.add,
            expand: true,
            onPressed: () => context.push(AddPastBookingPage()),
          ),
          const SizedBox(height: TappedSpacing.xs),
          Text(
            'it helps you get more gigs',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
                ),
          ),
        ],
      ),
    );
  }

  Widget _rail(
    BuildContext context, {
    required bool isCurrentUser,
    required List<Booking> bookings,
    required UserModel visitedUser,
  }) {
    if (bookings.isEmpty && isCurrentUser) {
      return _addBookingsButton(context);
    }

    return Column(
      children: [
        SizedBox(
          height: 210,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(
              horizontal: GlassMetrics.edgeInset,
            ),
            itemCount: bookings.length,
            separatorBuilder: (_, __) =>
                const SizedBox(width: TappedSpacing.sm),
            itemBuilder: (context, index) => BookingCard(
              booking: bookings[index],
              visitedUser: visitedUser,
            ),
          ),
        ),
        if (isCurrentUser) _addBookingsButton(context),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        final latestBookings = state.latestBookings;
        final isCurrentUser = state.isCurrentUser;
        final isVenue = state.visitedUser.venueInfo.isSome();
        if (latestBookings.isEmpty && !isCurrentUser) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GlassSectionTitle(
              'booking history',
              actionLabel: latestBookings.isEmpty ? null : 'see all',
              onAction: latestBookings.isEmpty
                  ? null
                  : () {
                      if (isVenue) {
                        showCupertinoModalBottomSheet<void>(
                          context: context,
                          backgroundColor: Colors.transparent,
                          builder: (context) => UserBookingsFeed(
                            userId: state.visitedUser.id,
                          ),
                        );
                        return;
                      }

                      context.push(
                        BookingHistoryPage(user: state.visitedUser),
                      );
                    },
            ),
            _rail(
              context,
              isCurrentUser: isCurrentUser,
              bookings: latestBookings,
              visitedUser: state.visitedUser,
            ),
          ],
        );
      },
    );
  }
}
