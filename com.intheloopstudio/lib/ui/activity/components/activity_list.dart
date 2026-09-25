import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intheloopapp/domains/activity_bloc/activity_bloc.dart';
import 'package:intheloopapp/domains/models/activity.dart';
import 'package:intheloopapp/ui/activity/components/activity_tile.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';

class ActivityList extends StatefulWidget {
  const ActivityList({super.key});

  @override
  State<ActivityList> createState() => _ActivityListState();
}

class _ActivityListState extends State<ActivityList> {
  final ScrollController _scrollController = ScrollController();
  late ActivityBloc _activityBloc;

  Timer? _debounce;

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;

    return currentScroll >= (maxScroll * 0.9);
  }

  void _onScroll() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (_isBottom) _activityBloc.add(FetchActivitiesEvent());
    });
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _activityBloc = context.read<ActivityBloc>();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Widget _activityListBuilder(BuildContext context, List<Activity> activities) {
    context.read<ActivityBloc>().add(const MarkAllAsReadEvent());
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      controller: _scrollController,
      slivers: activities.isEmpty
          ? const <Widget>[
              SliverFillRemaining(
                hasScrollBody: false,
                child: GlassEmptyState(
                  icon: CupertinoIcons.bell,
                  title: "you're all caught up",
                  message: 'booking requests, reminders, and new followers '
                      'will show up here',
                ),
              ),
            ]
          : <Widget>[
              const SliverToBoxAdapter(
                child: SizedBox(height: TappedSpacing.sm),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int index) {
                    return index >= activities.length
                        ? const Padding(
                            padding: EdgeInsets.all(TappedSpacing.lg),
                            child: Center(child: GlassLoading()),
                          )
                        : ActivityTile(
                            activity: activities[index],
                          );
                  },
                  childCount: activities.length + 1,
                ),
              ),
              const SliverToBoxAdapter(
                child: SizedBox(height: GlassMetrics.bottomBarClearance),
              ),
            ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ActivityBloc, ActivityState>(
      builder: (context, state) {
        return RefreshIndicator(
          onRefresh: () async =>
              context.read<ActivityBloc>().add(InitListenerEvent()),
          child: switch (state) {
            ActivityInitial() => const Center(child: GlassLoading()),
            ActivityFailure() => const GlassEmptyState(
                icon: CupertinoIcons.exclamationmark_triangle,
                title: 'failed to fetch activities',
              ),
            ActivitySuccess(:final activities) ||
            ActivityEnd(:final activities) =>
              _activityListBuilder(context, activities),
          },
        );
      },
    );
  }
}
