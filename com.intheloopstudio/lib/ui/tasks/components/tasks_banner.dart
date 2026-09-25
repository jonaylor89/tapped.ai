import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/domains/bookings_bloc/bookings_bloc.dart';
import 'package:intheloopapp/domains/models/booking.dart';
import 'package:intheloopapp/domains/models/social_following.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:intheloopapp/utils/current_user_builder.dart';

class TasksBanner extends StatelessWidget {
  const TasksBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final database = context.database;
    return CurrentUserBuilder(
      builder: (context, currentUser) {
        return FutureBuilder(
          future: database.getContactedVenues(currentUser.id),
          builder: (context, snapshot) {
            return BlocBuilder<BookingsBloc, BookingsState>(
              builder: (context, state) {
                final contactedVenuesCount = snapshot.data?.length ?? 1;
                final genres = currentUser.performerInfo
                    .map((p) => p.genres)
                    .getOrElse(() => []);
                final audienceSize = currentUser.socialFollowing.audienceSize;
                final bookings = state.bookings.where(
                  (booking) => booking.status == BookingStatus.confirmed,
                );

                final tasks = [
                  genres.isNotEmpty,
                  audienceSize > 0,
                  bookings.isNotEmpty,
                  contactedVenuesCount > 0,
                ];
                final incompleteTasks = tasks.where((t) => !t);

                if (incompleteTasks.isEmpty) {
                  return const SizedBox.shrink();
                }

                final n = incompleteTasks.length;
                return GlassBanner(
                  icon: CupertinoIcons.checkmark_circle,
                  tint: Theme.of(context).colorScheme.primary,
                  title: 'finish setting up',
                  message: '$n ${n == 1 ? 'task' : 'tasks'} left to get booked',
                  onAction: () => context.push(TasksPage()),
                );
              },
            );
          },
        );
      },
    );
  }
}
