import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/profile/profile_cubit.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';

class MessageButton extends StatelessWidget {
  const MessageButton({super.key});

  @override
  Widget build(BuildContext context) {
    final stream = context.stream;
    final nav = context.nav;
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        return GlassButton(
          label: 'message',
          icon: CupertinoIcons.bubble_left_fill,
          expand: true,
          onPressed: () async {
            final channel = await stream.createSimpleChat(state.visitedUser.id);
            nav.push(StreamChannelPage(channel: channel));
          },
        );
      },
    );
  }
}
