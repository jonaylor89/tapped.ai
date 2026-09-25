import 'package:flutter/material.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:intheloopapp/domains/models/performer_info.dart';
import 'package:intheloopapp/domains/models/social_following.dart';
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/profile/profile_view.dart';
import 'package:intheloopapp/ui/user_avatar.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:intheloopapp/utils/current_user_builder.dart';
import 'package:intl/intl.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:skeletons/skeletons.dart';

class UserTile extends StatefulWidget {
  const UserTile({
    required this.userId,
    required this.user,
    this.showFollowButton = true,
    this.subtitle,
    this.trailing,
    this.onTap,
    super.key,
  });

  final String userId;
  final Option<UserModel> user;
  final bool showFollowButton;
  final Widget? subtitle;
  final Widget? trailing;
  final void Function()? onTap;

  @override
  State<UserTile> createState() => _UserTileState();
}

class _UserTileState extends State<UserTile> {
  bool followingOverride = false;

  Widget? _buildSubtitle(UserModel user) {
    final widgetSubtitle = widget.subtitle;
    if (widgetSubtitle != null) return widgetSubtitle;

    final capacity = user.venueInfo.flatMap((t) => t.capacity);
    final socialFollowing = user.socialFollowing;
    final category = user.performerInfo.map((t) => t.category);
    return switch ((capacity, category)) {
      (None(), None()) =>
        socialFollowing.audienceSize == 0
            ? null
            : Text(
                '${NumberFormat.compactCurrency(
                  decimalDigits: 0,
                  symbol: '',
                ).format(socialFollowing.audienceSize)} followers',
              ),
      (None(), Some(:final value)) => Text(
        '${value.formattedName} performer'.toLowerCase(),
        style: TextStyle(color: value.color),
      ),
      (Some(:final value), _) => Text('$value capacity venue'),
    };
  }

  Widget _newBadge(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: TappedSpacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(GlassRadius.capsule),
      ),
      child: const Text(
        'new',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildUserTile(
    BuildContext context,
    UserModel user,
  ) {
    if (user.deleted) return const SizedBox.shrink();

    final database = context.database;
    return CurrentUserBuilder(
      errorWidget: const GlassListTile(
        leading: UserAvatar(radius: 25),
        title: 'ERROR',
        subtitle: "something isn't working right :/",
      ),
      builder: (context, currentUser) {
        return FutureBuilder<bool>(
          future: database.isVerified(widget.userId),
          builder: (context, snapshot) {
            final verified = snapshot.data ?? false;
            final isNew = user.timestamp.fold(
              () => false,
              (timestamp) => timestamp.isAfter(
                DateTime.now().subtract(const Duration(days: 7)),
              ),
            );
            final isVenue = user.venueInfo.isSome();

            return GlassListTile(
              leading: UserAvatar(
                radius: 25,
                pushUser: Option.of(user),
                imageUrl: user.profilePicture,
                verified: verified,
                square: isVenue,
              ),
              titleWidget: Row(
                children: [
                  Flexible(
                    child: Text(
                      user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (isNew) _newBadge(context),
                ],
              ),
              subtitleWidget: _buildSubtitle(user),
              trailing: widget.trailing,
              showChevron: widget.trailing == null,
              onTap:
                  widget.onTap ??
                  () {
                    showCupertinoModalBottomSheet<void>(
                      context: context,
                      builder: (context) {
                        return ProfileView(
                          visitedUserId: user.id,
                          visitedUser: Option.of(user),
                        );
                      },
                    );
                  },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final database = context.database;
    return switch (widget.user) {
      None() => FutureBuilder<Option<UserModel>>(
        future: database.getUserById(widget.userId),
        builder: (context, snapshot) {
          final data = snapshot.data;
          return switch (data) {
            null => SkeletonListTile(),
            None() => SkeletonListTile(),
            Some(:final value) => _buildUserTile(context, value),
          };
        },
      ),
      Some(:final value) => _buildUserTile(context, value),
    };
  }
}
