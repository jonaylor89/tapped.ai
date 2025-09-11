import 'package:flutter/material.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:stream_chat_flutter/stream_chat_flutter.dart';

class ChannelPreview extends StatelessWidget {
  const ChannelPreview({
    required this.channel,
    super.key,
  });

  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final lastMessage = channel.state?.messages.reversed
        .firstWhere((message) => !message.isDeleted);

    const maxLength = 124;
    final lastMessageText = lastMessage?.text ?? '';
    final isLonger = lastMessageText.length > maxLength;
    final messagePreview = isLonger
        ? '${lastMessageText.substring(0, maxLength)}...'
        : lastMessageText;
    final subtitle = lastMessage == null
        ? 'nothing yet'
        : messagePreview;
    // final opacity = (channel.state?.unreadCount ?? 0) > 0 ? 1.0 : 0.5;

    return ListTile(
      tileColor: Theme.of(context).colorScheme.surface,
      onTap: () {
        context.push(StreamChannelPage(channel: channel));
      },
      leading: StreamChannelAvatar(channel: channel),
      title: StreamChannelName(
        channel: channel,
      ),
      subtitle: Text(subtitle),
      trailing: channel.state!.unreadCount > 0
          ? CircleAvatar(
              radius: 10,
              child: Text(channel.state!.unreadCount.toString()),
            )
          : const SizedBox(),
    );
  }
}
