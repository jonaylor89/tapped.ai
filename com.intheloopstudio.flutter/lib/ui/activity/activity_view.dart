import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/activity/components/activity_list.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';

class ActivityView extends StatelessWidget {
  const ActivityView({super.key});

  @override
  Widget build(BuildContext context) {
    return const GlassPage(
      title: 'notifications',
      slivers: [
        SliverFillRemaining(child: ActivityList()),
      ],
    );
  }
}
