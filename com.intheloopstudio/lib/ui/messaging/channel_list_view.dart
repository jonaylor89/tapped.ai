import 'package:cancelable_retry/cancelable_retry.dart';
import 'package:flutter/material.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/loading/loading_view.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:intheloopapp/utils/current_user_builder.dart';
import 'package:stream_chat_flutter/stream_chat_flutter.dart'
    hide ChannelName;

class ChannelListView extends StatefulWidget {
  const ChannelListView({
    required this.client,
    super.key,
  });

  final StreamChatClient client;

  @override
  State<ChannelListView> createState() => _ChannelListViewState();
}

class _ChannelListViewState extends State<ChannelListView> {
  late final _controller = StreamChannelListController(
    client: widget.client,
    filter: Filter.in_(
      'members',
      [StreamChat.of(context).currentUser!.id],
    ),
    channelStateSort: const [SortOption('last_message_at')],
    limit: 20,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CurrentUserBuilder(
      builder: (context, currentUser) {
        final future = CancelableRetry(
          () => context.stream.connectUser(currentUser.id),
          retryIf: (bool result) => !result,
        );

        return FutureBuilder<bool>(
          future: future.run(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const LoadingView();
            }

            return RefreshIndicator(
              onRefresh: _controller.refresh,
              child: StreamChannelListView(
                controller: _controller,
                // emptyBuilder: _buildEmptyFeed,
                itemBuilder: (
                  BuildContext context,
                  List<Channel> channels,
                  int index,
                  StreamChannelListTile defaultChannelTile,
                ) {
                  // final channel = channels[index];
                  // return ChannelPreview(channel: channel);
                  return defaultChannelTile;
                },
                onChannelTap: (channel) {
                  context.push(StreamChannelPage(channel: channel));
                },
              ),
            );
          },
        );
      },
    );
  }
}
