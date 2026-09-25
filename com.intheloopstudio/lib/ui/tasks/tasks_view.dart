import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/domains/bookings_bloc/bookings_bloc.dart';
import 'package:intheloopapp/domains/models/booking.dart';
import 'package:intheloopapp/domains/models/social_following.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:intheloopapp/utils/current_user_builder.dart';

typedef _Task = ({
  bool isCompleted,
  String title,
  String description,
  TappedRoute whereToFix,
});

/// Profile-completion checklist: a progress ring header and a grouped list
/// of tasks, each deep-linking to where it can be fixed.
class TasksView extends StatelessWidget {
  const TasksView({super.key});

  Widget _taskTile(BuildContext context, _Task task) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.45);
    return GlassListTile(
      leading: Icon(
        task.isCompleted
            ? CupertinoIcons.checkmark_circle_fill
            : CupertinoIcons.circle,
        size: 26,
        color: task.isCompleted ? TappedColors.success : muted,
      ),
      titleWidget: Text(
        task.title,
        style: task.isCompleted
            ? TextStyle(
                color: muted,
                decoration: TextDecoration.lineThrough,
              )
            : null,
      ),
      subtitle: task.description,
      showChevron: !task.isCompleted,
      onTap: task.isCompleted ? null : () => context.push(task.whereToFix),
    );
  }

  @override
  Widget build(BuildContext context) {
    final database = context.database;
    final theme = Theme.of(context);
    return CurrentUserBuilder(
      builder: (context, currentUser) {
        return FutureBuilder(
          future: database.getContactedVenues(currentUser.id),
          builder: (context, snapshot) {
            return BlocBuilder<BookingsBloc, BookingsState>(
              builder: (context, bookingsState) {
                final contactedVenuesCount = snapshot.data?.length ?? 0;
                final genres = currentUser.performerInfo
                    .map((p) => p.genres)
                    .getOrElse(() => []);
                final audienceSize = currentUser.socialFollowing.audienceSize;
                final bookings = bookingsState.bookings.where(
                  (booking) => booking.status == BookingStatus.confirmed,
                );

                final tasks = <_Task>[
                  (
                    title: 'add a profile picture',
                    description: 'add a profile picture to your account',
                    isCompleted: currentUser.profilePicture.fold(
                      () => false,
                      (url) => url.isNotEmpty,
                    ),
                    whereToFix: SettingsPage(),
                  ),
                  (
                    title: 'add genres',
                    description: 'add what genres you perform',
                    isCompleted: genres.isNotEmpty,
                    whereToFix: SettingsPage(),
                  ),
                  (
                    title: 'add social following',
                    description:
                        'let promoters know how big your online presence is',
                    isCompleted: audienceSize > 0,
                    whereToFix: SettingsPage(),
                  ),
                  (
                    title: 'add booking history',
                    description: 'your past gigs are probably the most '
                        'important part of your profile',
                    isCompleted: bookings.isNotEmpty,
                    whereToFix: AddPastBookingPage(),
                  ),
                  (
                    title: 'contact your first venue',
                    description:
                        'contact venues to get your first gig on tapped!',
                    isCompleted: contactedVenuesCount > 0,
                    whereToFix: GigSearchPage(),
                  ),
                ];

                final done = tasks.where((t) => t.isCompleted).length;
                final progress = done / tasks.length;

                return GlassPage(
                  title: 'tasks',
                  subtitle: done == tasks.length
                      ? 'your profile is complete'
                      : '$done of ${tasks.length} complete',
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: GlassMetrics.edgeInset,
                        ),
                        child: GlassCard(
                          child: Row(
                            children: [
                              SizedBox(
                                width: 64,
                                height: 64,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    CircularProgressIndicator(
                                      value: progress,
                                      strokeWidth: 7,
                                      strokeCap: StrokeCap.round,
                                      backgroundColor: theme
                                          .colorScheme.onSurface
                                          .withValues(alpha: 0.1),
                                      color: TappedColors.success,
                                    ),
                                    Center(
                                      child: Text(
                                        '${(progress * 100).round()}%',
                                        style: theme.textTheme.labelLarge
                                            ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: TappedSpacing.lg),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'complete your profile',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'complete profiles get booked '
                                      '3x more often',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: GlassSection(
                        header: 'to do',
                        children: [
                          for (final task in tasks) _taskTile(context, task),
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
