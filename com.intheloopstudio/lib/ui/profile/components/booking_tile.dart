import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/domains/models/booking.dart';
import 'package:intheloopapp/domains/models/service.dart';
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:intheloopapp/utils/linkify.dart';
import 'package:timeago/timeago.dart' as timeago;

/// Compact list row for a past/upcoming booking: flier thumbnail, role
/// label, relative date, and a linkified description.
class BookingTile extends StatelessWidget {
  const BookingTile({
    required this.booking,
    required this.visitedUser,
    super.key,
  });

  final Booking booking;
  final UserModel visitedUser;

  Widget _row(
    BuildContext context, {
    required ImageProvider image,
    required String role,
    required String description,
  }) {
    final theme = Theme.of(context);
    return GlassListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image(
          image: image,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
        ),
      ),
      titleWidget: Row(
        children: [
          Text(
            role,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: TappedSpacing.sm),
          Text(
            timeago.format(booking.startTime, allowFromNow: true),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
      trailing: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Linkify(text: description),
      ),
      onTap: () => context.push(BookingPage(booking: booking)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final database = context.database;
    return Padding(
      padding: const EdgeInsets.only(bottom: TappedSpacing.sm),
      child: LiquidGlass(
        shape: RoundedRectangleBorder(borderRadius: GlassRadius.cardAll),
        child: switch (booking.requesterId) {
          None() => FutureBuilder(
              future: database.getUserById(booking.requesteeId),
              builder: (context, snapshot) {
                final requestee = snapshot.data;
                return switch (requestee) {
                  null => const SizedBox(
                      height: 64,
                      child: Center(child: GlassLoading()),
                    ),
                  None() => const SizedBox.shrink(),
                  Some(:final value) => _row(
                      context,
                      image: booking.getBookingImage(const None()),
                      role: 'performer',
                      description:
                          '@${value.username}${booking.name.map((t) => ' - $t').getOrElse(() => '')}',
                    ),
                };
              },
            ),
          Some(:final value) => FutureBuilder<
                (
                  Option<UserModel>,
                  Option<UserModel>,
                  Option<Service>,
                )>(
              future: () async {
                final [
                  requester as Option<UserModel>,
                  requestee as Option<UserModel>,
                  service as Option<Service>,
                ] = await Future.wait(
                  [
                    database.getUserById(value),
                    database.getUserById(booking.requesteeId),
                    () async {
                      return switch (booking.serviceId) {
                        None() => const None(),
                        Some(:final value) => database.getServiceById(
                            booking.requesteeId,
                            value,
                          ),
                      };
                    }(),
                  ],
                );

                return (requester, requestee, service);
              }(),
              builder: (context, snapshot) {
                final (
                  Option<UserModel> requester,
                  Option<UserModel> requestee,
                  Option<Service> service,
                ) = snapshot.data ??
                    (
                      const None(),
                      const None(),
                      const None(),
                    );

                final requesterUsername = switch (requester) {
                  None() => 'UNKNOWN',
                  Some(:final value) => '@${value.username}',
                };

                final requesteeUsername = switch (requestee) {
                  None() => 'UNKNOWN',
                  Some(:final value) => '@${value.username}',
                };

                final serviceTitle = switch (service) {
                  None() => '',
                  Some(:final value) => 'for ${value.title}',
                };
                return _row(
                  context,
                  image: booking.getBookingImage(requester),
                  role: visitedUser.id == booking.requesteeId
                      ? 'performer'
                      : 'booker',
                  description:
                      '$requesterUsername booked $requesteeUsername $serviceTitle',
                );
              },
            ),
        },
      ),
    );
  }
}
