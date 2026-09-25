import 'package:enum_to_string/enum_to_string.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/data/database_repository.dart';
import 'package:intheloopapp/domains/models/booking.dart';
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/user_avatar.dart';
import 'package:intheloopapp/utils/current_user_builder.dart';
import 'package:timeago/timeago.dart' as timeago;

/// A booking summarised as a glass row: counterpart avatar, relative date,
/// and a status pill. Pending requests aimed at the current user expose an
/// accept/deny action sheet.
class BookingContainer extends StatelessWidget {
  const BookingContainer({
    required this.booking,
    this.onConfirm,
    this.onDeny,
    super.key,
  });

  final Booking booking;
  final void Function(Booking)? onConfirm;
  final void Function(Booking)? onDeny;

  Color _statusColor(BookingStatus status) => switch (status) {
        BookingStatus.pending => Colors.orange,
        BookingStatus.confirmed => TappedColors.success,
        BookingStatus.canceled => TappedColors.error,
      };

  Widget _placeholder() => const Padding(
        padding: EdgeInsets.symmetric(
          horizontal: GlassMetrics.edgeInset,
          vertical: TappedSpacing.xs,
        ),
        child: GlassCard(
          padding: EdgeInsets.all(TappedSpacing.md),
          child: SizedBox(height: 44, child: Center(child: GlassLoading())),
        ),
      );

  Future<void> _showRequestActions(
    BuildContext context,
    DatabaseRepository database,
  ) {
    return showGlassActionSheet(
      context: context,
      title: 'booking request',
      message: 'accept or deny the request',
      actions: [
        GlassAction(
          label: 'accept',
          icon: CupertinoIcons.checkmark_circle_fill,
          onPressed: () {
            final updated = booking.copyWith(
              status: BookingStatus.confirmed,
            );
            database.updateBooking(updated);
            onConfirm?.call(updated);
          },
        ),
        GlassAction(
          label: 'deny',
          icon: CupertinoIcons.xmark_circle_fill,
          destructive: true,
          onPressed: () {
            final updated = booking.copyWith(
              status: BookingStatus.canceled,
            );
            database.updateBooking(updated);
            onDeny?.call(updated);
          },
        ),
      ],
    );
  }

  Widget _row(
    BuildContext context, {
    required DatabaseRepository database,
    required Option<UserModel> counterpart,
    required bool canRespond,
  }) {
    final theme = Theme.of(context);
    return switch (counterpart) {
      None() => _placeholder(),
      Some(:final value) => FutureBuilder<bool>(
          future: database.isVerified(value.id),
          builder: (context, snapshot) {
            final isVerified = snapshot.data ?? false;
            final statusColor = _statusColor(booking.status);
            final pending = booking.status == BookingStatus.pending;

            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: GlassMetrics.edgeInset,
                vertical: TappedSpacing.xs,
              ),
              child: GlassCard(
                padding: const EdgeInsets.all(TappedSpacing.md),
                onTap: () => context.push(BookingPage(booking: booking)),
                child: Row(
                  children: [
                    UserAvatar(
                      radius: 22,
                      pushUser: counterpart,
                      imageUrl: value.profilePicture,
                      verified: isVerified,
                    ),
                    const SizedBox(width: TappedSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            value.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            timeago.format(
                              booking.startTime,
                              allowFromNow: true,
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: TappedSpacing.sm),
                    if (canRespond && pending)
                      GlassIconButton(
                        icon: CupertinoIcons.ellipsis,
                        size: 36,
                        semanticsLabel: 'respond to request',
                        onPressed: () => _showRequestActions(context, database),
                      )
                    else
                      GlassPill(
                        label: EnumToString.convertToString(booking.status),
                        tint: statusColor,
                        foreground: statusColor,
                      ),
                  ],
                ),
              ),
            );
          },
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final database = RepositoryProvider.of<DatabaseRepository>(context);

    return switch (booking.requesterId) {
      None() => const SizedBox.shrink(),
      Some(:final value) => CurrentUserBuilder(
          errorWidget: const GlassEmptyState(
            icon: CupertinoIcons.exclamationmark_triangle,
            title: "something isn't working right",
          ),
          builder: (context, currentUser) {
            final isRequester = currentUser.id == value;
            final counterpartId = isRequester ? booking.requesteeId : value;
            return FutureBuilder<Option<UserModel>>(
              future: database.getUserById(counterpartId),
              builder: (context, snapshot) {
                final counterpart = snapshot.data;
                if (counterpart == null) return _placeholder();
                return _row(
                  context,
                  database: database,
                  counterpart: counterpart,
                  canRespond: !isRequester,
                );
              },
            );
          },
        ),
    };
  }
}
