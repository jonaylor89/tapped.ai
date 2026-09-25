import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/domains/models/booking.dart';
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/ui/booking/booking_view.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:intheloopapp/utils/hero_image.dart';
import 'package:intl/intl.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:uuid/uuid.dart';

/// Poster-style card for a single past gig.
class BookingCard extends StatelessWidget {
  const BookingCard({
    required this.booking,
    required this.visitedUser,
    super.key,
  });

  final Booking booking;
  final UserModel visitedUser;

  @override
  Widget build(BuildContext context) {
    final database = context.database;
    final isRequester = switch (booking.requesterId) {
      None() => false,
      Some(:final value) => visitedUser.id == value,
    };
    final formatted = DateFormat.MMMd().format(booking.startTime);

    return FutureBuilder(
      future: switch ((booking.requesterId, isRequester)) {
        (None(), _) => database.getUserById(booking.requesteeId),
        (Some(), true) => database.getUserById(booking.requesteeId),
        (Some(:final value), false) => database.getUserById(value),
      },
      builder: (context, snapshot) {
        final user = snapshot.data ?? const None();
        final imageProvider = booking.getBookingImage(user);
        final heroTag = const Uuid().v4();

        final titleText = booking.name.fold(
          () => user.fold(() => 'booking', (t) => t.displayName),
          (t) => t,
        );

        return Hero(
          tag: heroTag,
          child: GlassImageCard(
            image: imageProvider,
            width: 160,
            height: 210,
            semanticsLabel: '$titleText, $formatted',
            topRight: GlassPill(
              label: formatted,
              icon: CupertinoIcons.calendar,
            ),
            onTap: () {
              showCupertinoModalBottomSheet<void>(
                context: context,
                backgroundColor: Colors.transparent,
                builder: (context) => BookingView(
                  booking: booking,
                  flierImage: Option.of(
                    HeroImage(
                      imageProvider: imageProvider,
                      heroTag: heroTag,
                    ),
                  ),
                ),
              );
            },
            child: Text(
              titleText.isEmpty ? 'booking' : titleText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                  ),
            ),
          ),
        );
      },
    );
  }
}
