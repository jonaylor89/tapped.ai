import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intheloopapp/domains/bookings_bloc/bookings_bloc.dart';
import 'package:intheloopapp/domains/models/booking.dart';
import 'package:intheloopapp/ui/booking_container/booking_container.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';

class BookingsList extends StatelessWidget {
  const BookingsList({
    required this.bookings,
    this.scrollController,
    super.key,
  });

  final List<Booking> bookings;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return bookings.isEmpty
        ? const GlassEmptyState(
            icon: CupertinoIcons.calendar,
            title: 'nothing yet',
          )
        : ListView(
            controller: scrollController,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: TappedSpacing.sm),
            children: bookings.map((e) {
              return BookingContainer(
                booking: e,
                onConfirm: (booking) => context.bookings.add(
                  ConfirmBooking(booking: booking),
                ),
                onDeny: (booking) => context.bookings.add(
                  DenyBooking(booking: booking),
                ),
              );
            }).toList(),
          );
  }
}
