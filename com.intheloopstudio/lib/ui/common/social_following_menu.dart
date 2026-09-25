import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class SocialFollowingMenu extends StatelessWidget {
  const SocialFollowingMenu({
    required this.user,
    super.key,
  });

  final UserModel user;

  @override
  Widget build(BuildContext context) {
    final facebookFollowers = user.socialFollowing.facebookFollowers;
    final facebookHandle = user.socialFollowing.facebookHandle;
    final instagramFollowers = user.socialFollowing.instagramFollowers;
    final instagramHandle = user.socialFollowing.instagramHandle;
    final twitterFollowers = user.socialFollowing.twitterFollowers;
    final twitterHandle = user.socialFollowing.twitterHandle;
    final tiktokFollowers = user.socialFollowing.tiktokFollowers;
    final tiktokHandle = user.socialFollowing.tiktokHandle;
    final formatter = NumberFormat.compact(locale: 'en');

    if (facebookFollowers <= 0 &&
        instagramFollowers <= 0 &&
        twitterFollowers <= 0 &&
        tiktokFollowers <= 0) {
      return const SizedBox.shrink();
    }

    GlassListTile tile({
      required IconData icon,
      required Color color,
      required String network,
      required int followers,
      required Option<String> handle,
      required String Function(String) urlOf,
    }) {
      return GlassListTile(
        leadingIcon: icon,
        leadingColor: color,
        title: network,
        subtitle: handle.fold(() => null, (h) => '@$h'),
        value: '${formatter.format(followers)} followers',
        showChevron: handle.isSome(),
        onTap: switch (handle) {
          None() => null,
          Some(:final value) => () => launchUrl(
            Uri.parse(urlOf(value)),
            mode: LaunchMode.externalApplication,
          ),
        },
      );
    }

    return GlassSection(
      header: 'audience',
      children: [
        if (facebookFollowers > 0)
          tile(
            icon: FontAwesomeIcons.facebook,
            color: const Color(0xff1877F2),
            network: 'facebook',
            followers: facebookFollowers,
            handle: facebookHandle,
            urlOf: (h) => 'https://facebook.com/$h',
          ),
        if (instagramFollowers > 0)
          tile(
            icon: FontAwesomeIcons.instagram,
            color: const Color(0xffE1306C),
            network: 'instagram',
            followers: instagramFollowers,
            handle: instagramHandle,
            urlOf: (h) => 'https://instagram.com/$h',
          ),
        if (twitterFollowers > 0)
          tile(
            icon: FontAwesomeIcons.twitter,
            color: const Color(0xff1DA1F2),
            network: 'twitter',
            followers: twitterFollowers,
            handle: twitterHandle,
            urlOf: (h) => 'https://twitter.com/$h',
          ),
        if (tiktokFollowers > 0)
          tile(
            icon: FontAwesomeIcons.tiktok,
            color: Colors.black,
            network: 'tiktok',
            followers: tiktokFollowers,
            handle: tiktokHandle,
            urlOf: (h) => 'https://tiktok.com/@$h',
          ),
      ],
    );
  }
}
