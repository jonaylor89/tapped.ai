import 'package:badges/badges.dart' as badges;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/ui/conditional_parent_widget.dart';
import 'package:intheloopapp/ui/profile/profile_view.dart';
import 'package:intheloopapp/utils/default_image.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    this.pushId = const None(),
    this.pushUser = const None(),
    this.imageUrl = const None(),
    this.radius,
    this.minRadius,
    this.maxRadius,
    this.verified = false,
    this.square = false,
    this.onTap,
  });

  final Option<String> pushId;
  final Option<UserModel> pushUser;
  final Option<String> imageUrl;
  final bool verified;
  final double? radius;
  final double? minRadius;
  final double? maxRadius;
  final bool square;
  final void Function()? onTap;

  Widget Function({
    required Widget child,
  })
  _pushProfile(BuildContext context) {
    return ({
      required Widget child,
    }) {
      if (onTap != null) {
        return GestureDetector(
          onTap: onTap,
          child: child,
        );
      }

      return switch ((pushId, pushUser)) {
        (None(), None()) => child,
        (Some(:final value), None()) => GestureDetector(
          onTap: () {
            showCupertinoModalBottomSheet<void>(
              context: context,
              builder: (context) {
                return ProfileView(
                  scrollController: ModalScrollController.of(context),
                  visitedUserId: value,
                  visitedUser: const None(),
                );
              },
            );

            // context.push(
            //   ProfilePage(
            //     userId: value.id,
            //     user: pushUser,
            //   ),
            // );
          },
        ),
        (_, Some(:final value)) => GestureDetector(
          onTap: () {
            showCupertinoModalBottomSheet<void>(
              context: context,
              builder: (context) {
                return ProfileView(
                  visitedUserId: value.id,
                  visitedUser: Option.of(value),
                );
              },
            );

            // context.push(
            //   ProfilePage(
            //     userId: value.id,
            //     user: pushUser,
            //   ),
            // );
          },
          child: child,
        ),
      };
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConditionalParentWidget(
      condition: pushId.isSome(),
      conditionalBuilder: _pushProfile(context),
      child: badges.Badge(
        position: badges.BadgePosition.bottomEnd(end: -5, bottom: -4),
        badgeContent: GestureDetector(
          onTap: () => showGlassSheet<void>(
            context: context,
            title: 'get verified',
            builder: (context) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    CupertinoIcons.checkmark_seal_fill,
                    color: theme.colorScheme.primary,
                    size: 28,
                  ),
                  const SizedBox(width: TappedSpacing.md),
                  Expanded(
                    child: Text(
                      'post a screenshot of your profile to your instagram '
                      'story and tag us @tappedai',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          child: const Icon(
            Icons.check,
            color: Colors.white,
            size: 10,
          ),
        ),
        showBadge: verified,
        badgeStyle: const badges.BadgeStyle(
          shape: badges.BadgeShape.twitter,
          badgeColor: Colors.blue,
        ),
        child: square
            ? Container(
                width: (radius ?? 20) * 2,
                height: (radius ?? 20) * 2,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  image: DecorationImage(
                    fit: BoxFit.cover,
                    image: imageUrl.fold(
                      () => getDefaultImage(pushId),
                      (t) {
                        if (t.isEmpty) {
                          return getDefaultImage(pushId);
                        }
                        return CachedNetworkImageProvider(
                          t,
                          errorListener: (object) {
                            return;
                          },
                        );
                      },
                    ),
                  ),
                ),
                child: CircleAvatar(
                  radius: radius,
                  foregroundImage: imageUrl.fold(
                    () => getDefaultImage(pushId),
                    (t) {
                      if (t.isEmpty) {
                        return getDefaultImage(pushId);
                      }
                      return CachedNetworkImageProvider(
                        t,
                        errorListener: (object) {
                          return;
                        },
                      );
                    },
                  ),
                  backgroundColor: Colors.black,
                ),
              )
            : CircleAvatar(
                radius: radius,
                minRadius: minRadius,
                maxRadius: maxRadius,
                foregroundImage: imageUrl.fold(
                  () => getDefaultImage(pushId),
                  (t) {
                    if (t.isEmpty) {
                      return getDefaultImage(pushId);
                    }
                    return CachedNetworkImageProvider(
                      t,
                      errorListener: (object) {
                        return;
                      },
                    );
                  },
                ),
                backgroundColor: Colors.black,
              ),
      ),
    );
  }
}
