import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/common/easter_egg_placeholder.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/messaging/search_text_field.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:intheloopapp/utils/premium_builder.dart';
import 'package:stream_chat_flutter/stream_chat_flutter.dart';

class ChannelList extends StatefulWidget {
  const ChannelList({super.key});

  @override
  State<ChannelList> createState() => _ChannelList();
}

class _ChannelList extends State<ChannelList> {
  final ScrollController _scrollController = ScrollController();

  Widget _buildEmptyFeed(BuildContext context) {
    final theme = Theme.of(context);
    return PremiumBuilder(
      builder: (context, isPremium) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            GlassMetrics.edgeInset,
            TappedSpacing.md,
            GlassMetrics.edgeInset,
            GlassMetrics.bottomBarClearance,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(GlassRadius.sheet),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const Image(
                  image: AssetImage('assets/classic_edm.gif'),
                  fit: BoxFit.cover,
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.8),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: TappedSpacing.xl,
                  right: TappedSpacing.xl,
                  bottom: TappedSpacing.xl,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const EasterEggPlaceholder(),
                      Text(
                        'no conversations yet',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: TappedSpacing.xs),
                      Text(
                        'start talking to venues and get the conversation '
                        'started',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                      if (!isPremium) ...[
                        const SizedBox(height: TappedSpacing.lg),
                        GlassButton.primary(
                          label: 'upgrade to message',
                          icon: CupertinoIcons.sparkles,
                          expand: true,
                          onPressed: () => context.push(PaywallPage()),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // late final StreamChannelListController _messageSearchListController =
  // StreamChannelListController(
  //   client: StreamChat.of(context).client,
  //   filter: Filter.and([
  //     Filter.in_('members', [StreamChat.of(context).currentUser!.id]),
  //     Filter.autoComplete('member.user.name', _controller.text),
  //   ]),
  //   limit: 5,
  // );
  //
  late final TextEditingController _controller = TextEditingController()
    ..addListener(_channelQueryListener);

  String _searchQuery = '';
  bool _isSearchActive = false;
  Timer? _debounce;

  void _channelQueryListener() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        // _messageSearchListController.searchQuery = _controller.text;
        // _messageSearchListController.filter = Filter.and([
        //   Filter.in_('members', [StreamChat.of(context).currentUser!.id]),
        //   Filter.query('member.user.name', _controller.text),
        // ]);
        setState(() {
          _searchQuery = _controller.text;
          _isSearchActive = _controller.text.isNotEmpty;
        });
        // if (_isSearchActive) _messageSearchListController.doInitialLoad();
      }
    });
  }

  late final _channelListController = StreamChannelListController(
    client: StreamChat.of(context).client,
    filter: Filter.in_(
      'members',
      [StreamChat.of(context).currentUser!.id],
    ),
    limit: 30,
  );

  @override
  void dispose() {
    _controller.removeListener(_channelQueryListener);
    _controller.dispose();
    _scrollController.dispose();
    _channelListController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (_) {
        if (_isSearchActive) {
          _controller.clear();
          setState(() => _isSearchActive = false);
        }
      },
      child: NotificationListener<ScrollUpdateNotification>(
        onNotification: (ScrollNotification scrollInfo) {
          if (_scrollController.position.userScrollDirection ==
              ScrollDirection.reverse) {
            FocusScope.of(context).unfocus();
          }
          return true;
        },
        child: NestedScrollView(
          controller: _scrollController,
          headerSliverBuilder: (_, __) => [
            SliverToBoxAdapter(
              child: SearchTextField(
                controller: _controller,
                showCloseButton: _isSearchActive,
              ),
            ),
          ],
          body: _isSearchActive
              ? StreamChannelListView(
                  controller: StreamChannelListController(
                    client: StreamChat.of(context).client,
                    filter: Filter.and([
                      Filter.in_('members', [
                        StreamChat.of(context).currentUser!.id,
                      ]),
                      if (_searchQuery.isNotEmpty)
                        Filter.autoComplete('member.user.name', _searchQuery),
                    ]),
                    limit: 5,
                  ),
                  emptyBuilder: (_) => const GlassEmptyState(
                    icon: CupertinoIcons.search,
                    title: 'no results',
                    message: 'try a different name',
                  ),
                  itemBuilder:
                      (
                        context,
                        messageResponses,
                        index,
                        defaultWidget,
                      ) {
                        return defaultWidget.copyWith(
                          onTap: () async {
                            final nav = context.nav;
                            final channel = messageResponses[index];
                            FocusScope.of(context).requestFocus(FocusNode());
                            if (channel.state == null) {
                              await channel.watch();
                            }

                            nav.push(
                              StreamChannelPage(
                                channel: channel,
                              ),
                            );
                          },
                        );
                      },
                )
              : SlidableAutoCloseBehavior(
                  // closeWhenOpened: true,
                  child: RefreshIndicator(
                    onRefresh: _channelListController.refresh,
                    child: StreamChannelListView(
                      controller: _channelListController,
                      itemBuilder: (context, channels, index, defaultWidget) {
                        final chatTheme = StreamChatTheme.of(context);
                        const backgroundColor = Colors.transparent;
                        final channel = channels[index];
                        final canDeleteChannel = channel.ownCapabilities
                            .contains(PermissionType.deleteChannel);
                        return Slidable(
                          groupTag: 'channels-actions',
                          endActionPane: ActionPane(
                            extentRatio: canDeleteChannel ? 0.40 : 0.20,
                            motion: const BehindMotion(),
                            children: [
                              CustomSlidableAction(
                                onPressed: (_) {
                                  showChannelInfoModalBottomSheet<void>(
                                    context: context,
                                    channel: channel,
                                    onViewInfoTap: () {
                                      Navigator.pop(context);
                                      // Navigate to info screen
                                    },
                                  );
                                },
                                backgroundColor: backgroundColor,
                                child: const Icon(Icons.more_horiz),
                              ),
                              if (canDeleteChannel)
                                CustomSlidableAction(
                                  backgroundColor: backgroundColor,
                                  child: StreamSvgIcon.delete(
                                    color: chatTheme.colorTheme.accentError,
                                  ),
                                  onPressed: (_) async {
                                    final res = await showConfirmationBottomSheet(
                                      context,
                                      title: 'delete conversation',
                                      question:
                                          'are you sure you want to delete this conversation?',
                                      okText: 'delete',
                                      cancelText: 'cancel',
                                      icon: StreamSvgIcon.delete(
                                        color: chatTheme.colorTheme.accentError,
                                      ),
                                    );
                                    if (res ?? false) {
                                      await _channelListController
                                          .deleteChannel(channel);
                                    }
                                  },
                                ),
                              // CustomSlidableAction(
                              //   backgroundColor: backgroundColor,
                              //   onPressed: (_) {
                              //     showChannelInfoModalBottomSheet(
                              //       context: context,
                              //       channel: channel,
                              //       onViewInfoTap: () {
                              //         Navigator.pop(context);
                              //         Navigator.push(
                              //           context,
                              //           MaterialPageRoute(
                              //             builder: (context) {
                              //               final isOneToOne =
                              //                   channel.memberCount == 2 &&
                              //                       channel.isDistinct;
                              //               return StreamChannel(
                              //                 channel: channel,
                              //                 child: isOneToOne
                              //                     ? ChatInfoScreen(
                              //                   messageTheme: chatTheme
                              //                       .ownMessageTheme,
                              //                   user: channel
                              //                       .state!.members
                              //                       .where((m) =>
                              //                   m.userId !=
                              //                       channel
                              //                           .client
                              //                           .state
                              //                           .currentUser!
                              //                           .id)
                              //                       .first
                              //                       .user,
                              //                 )
                              //                     : GroupInfoScreen(
                              //                   messageTheme: chatTheme
                              //                       .ownMessageTheme,
                              //                 ),
                              //               );
                              //             },
                              //           ),
                              //         );
                              //       },
                              //     );
                              //   },
                              //   child: const Icon(Icons.more_horiz),
                              // ),
                              // if (canDeleteChannel)
                              //   CustomSlidableAction(
                              //     backgroundColor: backgroundColor,
                              //     child: StreamSvgIcon.delete(
                              //       color: chatTheme.colorTheme.accentError,
                              //     ),
                              //     onPressed: (_) async {
                              //       final res =
                              //       await showConfirmationBottomSheet(
                              //         context,
                              //         title: 'Delete Conversation',
                              //         question:
                              //         'Are you sure you want to delete this conversation?',
                              //         okText: 'Delete',
                              //         cancelText: 'Cancel',
                              //         icon: StreamSvgIcon.delete(
                              //           color: chatTheme.colorTheme.accentError,
                              //         ),
                              //       );
                              //       if (res) {
                              //         await _channelListController
                              //             .deleteChannel(channel);
                              //       }
                              //     },
                              //   ),
                            ],
                          ),
                          child: defaultWidget,
                        );
                      },
                      onChannelTap: (channel) {
                        context.push(StreamChannelPage(channel: channel));
                      },
                      emptyBuilder: _buildEmptyFeed,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
