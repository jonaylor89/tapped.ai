import 'package:cancelable_retry/cancelable_retry.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/common/easter_egg_placeholder.dart';
import 'package:intheloopapp/ui/loading/loading_view.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:intheloopapp/utils/current_user_builder.dart';
import 'package:intheloopapp/utils/premium_builder.dart';
import 'package:stream_chat_flutter/stream_chat_flutter.dart'
    hide ChannelName, ChannelPreview;

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

  Widget _buildEmptyFeed(BuildContext context) {
    return PremiumBuilder(
      builder: (context, isPremium) {
        return SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              child: Container(
                height: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                      spreadRadius: 5,
                    ),
                  ],
                  image: const DecorationImage(
                    image: AssetImage('assets/classic_edm.gif'),
                    fit: BoxFit.cover,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 12,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                        decoration: const BoxDecoration(
                          color: Colors.black,
                        ),
                        child: Column(
                          children: [
                            const EasterEggPlaceholder(),
                            const Text(
                              'start talking to venues and get the conversation started!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 20),
                            if (!isPremium)
                              CupertinoButton(
                                borderRadius: BorderRadius.circular(15),
                                child: const Text(
                                  'upgrade',
                                ),
                                onPressed: () => context.push(
                                  PaywallPage(),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
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
