import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/messaging/channel_name.dart';
import 'package:stream_chat_flutter/stream_chat_flutter.dart' hide ChannelName;

/// ![screenshot](https://raw.githubusercontent.com/GetStream/stream-chat-flutter/master/screenshots/channel_header.png)
/// ![screenshot](https://raw.githubusercontent.com/GetStream/stream-chat-flutter/master/screenshots/channel_header_paint.png)
///
/// It shows the current [Channel] information.
///
/// ```dart
/// class MyApp extends StatelessWidget {
///   final StreamChatClient client;
///   final Channel channel;
///
///   MyApp(this.client, this.channel);
///
///   @override
///   Widget build(BuildContext context) {
///     return MaterialApp(
///       home: StreamChat(
///         client: client,
///         child: StreamChannel(
///           channel: channel,
///           child: Scaffold(
///             appBar: ChannelHeader(),
///           ),
///         ),
///       ),
///     );
///   }
/// }
/// ```
///
/// Usually you would use this widget as an [AppBar] inside a [Scaffold].
/// However you can also use it as a normal widget.
///
/// Make sure to have a [StreamChannel] ancestor in order to provide the
/// information about the channel.
/// Every part of the widget uses a [StreamBuilder] to render the channel
/// information as soon as it updates.
///
/// By default the widget shows a backButton that calls [Navigator.pop].
/// You can disable this button using the [showBackButton] property of just
/// override the behaviour
/// with [onBackPressed].
///
/// The widget components render the ui based on the first ancestor of type
/// [StreamChatTheme] and on its ChannelTheme.channelHeaderTheme property.
/// Modify it to change the widget appearance.
class ChannelHeader extends StatelessWidget implements PreferredSizeWidget {
  /// Creates a channel header
  const ChannelHeader({
    super.key,
    this.showBackButton = true,
    this.onBackPressed,
    this.onTitleTap,
    this.showTypingIndicator = true,
    this.onImageTap,
    this.showConnectionStateTile = false,
    this.title,
    this.subtitle,
    this.leading,
    this.actions,
    // ignore: avoid_field_initializers_in_const_classes
  }) : preferredSize = const Size.fromHeight(kToolbarHeight);

  /// True if this header shows the leading back button
  final bool showBackButton;

  /// Callback to call when pressing the back button.
  /// By default it calls [Navigator.pop]
  final VoidCallback? onBackPressed;

  /// Callback to call when the header is tapped.
  final VoidCallback? onTitleTap;

  /// Callback to call when the image is tapped.
  final VoidCallback? onImageTap;

  /// If true the typing indicator will be rendered if a user is typing
  final bool showTypingIndicator;

  /// Show connection tile on header
  final bool showConnectionStateTile;

  /// Title widget
  final Widget? title;

  /// Subtitle widget
  final Widget? subtitle;

  /// Leading widget
  final Widget? leading;

  /// AppBar actions
  /// By default it shows the [StreamChannelAvatar]
  final List<Widget>? actions;

  // Call _startCall(BuildContext context) {
  //   final currentUser = StreamChat.of(context).currentUser;
  //   final channel = StreamChannel.of(context).channel;
  //   final stream = context.stream;

  //   final call = stream.makeVideoCall(
  //     participantIds: channel.state!.members
  //         .where(
  //           (e) => e.userId != currentUser?.id,
  //         )
  //         .map((e) => e.userId)
  //         .whereType<String>()
  //         .toList(),
  //   );

  //   channel.sendMessage(
  //     Message(
  //       attachments: [
  //         Attachment(
  //           type: 'custom',
  //           authorName: currentUser?.name ?? '',
  //           uploadState: const UploadState.success(),
  //           extraData: {
  //             'callCid': call.callCid,
  //           },
  //         ),
  //       ],
  //     ),
  //   );

  //   return call;
  // }

  @override
  Widget build(BuildContext context) {
    final channel = StreamChannel.of(context).channel;

    final leadingWidget =
        leading ??
        (showBackButton
            ? StreamBackButton(
                onPressed: onBackPressed,
                showUnreadCount: true,
              )
            : const SizedBox());

    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.55);

    return StreamConnectionStatusBuilder(
      statusBuilder: (context, status) {
        var statusString = '';
        var showStatus = true;

        switch (status) {
          case ConnectionStatus.connected:
            statusString = context.translations.connectedLabel;
            showStatus = false;
          case ConnectionStatus.connecting:
            statusString = context.translations.reconnectingLabel;
          case ConnectionStatus.disconnected:
            statusString = context.translations.disconnectedLabel;
        }

        return StreamInfoTile(
          showMessage: showConnectionStateTile && showStatus,
          message: statusString,
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: GlassBlur.regular,
                sigmaY: GlassBlur.regular,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withValues(alpha: 0.55),
                  border: Border(
                    bottom: BorderSide(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.08,
                      ),
                    ),
                  ),
                ),
                child: AppBar(
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  leading: leadingWidget,
                  actions:
                      actions ??
                      [
                        Padding(
                          padding: const EdgeInsets.only(
                            right: GlassMetrics.edgeInset,
                          ),
                          child: Center(
                            child: StreamChannelAvatar(
                              onTap: onImageTap,
                              channel: channel,
                            ),
                          ),
                        ),
                      ],
                  centerTitle: true,
                  title: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onTitleTap,
                    child: SizedBox(
                      height: preferredSize.height,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          title ?? const ChannelName(),
                          const SizedBox(height: 2),
                          subtitle ??
                              StreamChannelInfo(
                                showTypingIndicator: showTypingIndicator,
                                channel: channel,
                                textStyle: theme.textTheme.labelSmall?.copyWith(
                                  color: muted,
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  final Size preferredSize;
}
