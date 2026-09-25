import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/activity/components/activity_row.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intheloopapp/domains/activity_bloc/activity_bloc.dart';
import 'package:intheloopapp/domains/models/activity.dart';

class SearchAppearanceActivityTile extends StatelessWidget {
  const SearchAppearanceActivityTile({
    required this.activity,
    super.key,
  });

  final SearchAppearance activity;

  @override
  Widget build(BuildContext context) {

    var markedRead = activity.markedRead;
    return BlocBuilder<ActivityBloc, ActivityState>(
      builder: (context, state) {
        if (!markedRead) {
          context
              .read<ActivityBloc>()
              .add(MarkActivityAsReadEvent(activity: activity));
          markedRead = true;
        }

        return ActivityRow(
          leading: const LiquidGlass.circle(
            width: 44,
            height: 44,
            child: Center(child: Icon(CupertinoIcons.search, size: 20)),
          ),
          title: 'people are finding you in search',
          message: "you've appeared in ${activity.count} searches recently",
          timestamp: activity.timestamp,
          unread: !activity.markedRead,
        );
      },
    );
  }
}
