import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/profile/profile_cubit.dart';
import 'package:url_launcher/url_launcher.dart';

class SocialMediaIcons extends StatelessWidget {
  const SocialMediaIcons({super.key});

  Widget? _socialMediaIcon({
    required Color color,
    required Widget icon,
    void Function()? onTap,
  }) {
    return Center(
      child: GlassPressable(
        onPressed: onTap,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.35),
              ),
            ),
            LiquidGlass.circle(
              width: GlassMetrics.control,
              height: GlassMetrics.control,
              variant: GlassVariant.regular,
              child: Center(child: icon),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        final socialFollowing = state.visitedUser.socialFollowing;
        final spotifyUrl = socialFollowing.spotifyId.map(
          (spotifyId) => 'https://open.spotify.com/artist/$spotifyId',
        );
        return SliverPadding(
          padding: const EdgeInsets.symmetric(
            horizontal: GlassMetrics.edgeInset,
            vertical: TappedSpacing.md,
          ),
          sliver: SliverGrid.count(
          crossAxisCount: 4,
          mainAxisSpacing: TappedSpacing.sm,
          children: [
            switch (socialFollowing.facebookHandle) {
              None() => null,
              Some(:final value) => _socialMediaIcon(
                  color: Colors.blue.shade900,
                  icon: Icon(
                    FontAwesomeIcons.facebook,
                    color: Colors.blue[900],
                  ),
                  onTap: () {
                    launchUrl(
                      Uri(
                        scheme: 'https',
                        path: 'facebook.com/$value',
                      ),
                    );
                  },
                ),
            },
            switch (socialFollowing.twitterHandle) {
              None() => null,
              Some(:final value) => _socialMediaIcon(
                  color: Colors.white,
                  icon: const Icon(
                    FontAwesomeIcons.xTwitter,
                    color: Colors.white,
                  ),
                  onTap: () {
                    launchUrl(
                      Uri(
                        scheme: 'https',
                        path: 'x.com/$value',
                      ),
                    );
                  },
                ),
            },
            switch (socialFollowing.instagramHandle) {
              None() => null,
              Some(:final value) => _socialMediaIcon(
                  color: Colors.pink,
                  icon: const Icon(
                    FontAwesomeIcons.instagram,
                    color: Colors.pink,
                  ),
                  onTap: () {
                    launchUrl(
                      Uri(
                        scheme: 'https',
                        path: 'instagram.com/$value',
                      ),
                    );
                  },
                ),
            },
            switch (socialFollowing.tiktokHandle) {
              None() => null,
              Some(:final value) => _socialMediaIcon(
                  color: Colors.black,
                  icon: const Icon(FontAwesomeIcons.tiktok),
                  onTap: () {
                    launchUrl(
                      Uri(
                        scheme: 'https',
                        path: 'tiktok.com/@$value',
                      ),
                    );
                  },
                ),
            },
            switch (socialFollowing.youtubeHandle) {
              None() => (() {
                  return switch (socialFollowing.youtubeChannelId) {
                    None() => null,
                    Some(:final value) => _socialMediaIcon(
                        color: Colors.red,
                        icon: Icon(
                          FontAwesomeIcons.youtube,
                          color: Colors.red.shade700,
                        ),
                        onTap: () {
                          launchUrl(
                            Uri(
                              scheme: 'https',
                              path: 'youtube.com/channel/$value',
                            ),
                          );
                        },
                      ),
                  };
                })(),
              Some(:final value) => _socialMediaIcon(
                  color: Colors.red,
                  icon: Icon(
                    FontAwesomeIcons.youtube,
                    color: Colors.red.shade700,
                  ),
                  onTap: () {
                    launchUrl(
                      Uri(
                        scheme: 'https',
                        path: 'youtube.com/@$value',
                      ),
                    );
                  },
                ),
            },
            switch (spotifyUrl) {
              None() => null,
              Some(:final value) => _socialMediaIcon(
                  color: Colors.green,
                  icon: const Icon(
                    FontAwesomeIcons.spotify,
                    color: Colors.green,
                  ),
                  onTap: () {
                    launchUrl(
                      Uri.parse(value),
                    );
                  },
                ),
            },
            switch (socialFollowing.soundcloudHandle) {
              None() => null,
              Some(:final value) => _socialMediaIcon(
                  color: Colors.orange,
                  icon: const Icon(
                    FontAwesomeIcons.soundcloud,
                    color: Colors.orange,
                  ),
                  onTap: () {
                    launchUrl(
                      Uri(
                        scheme: 'https',
                        path: 'soundcloud.com/$value',
                      ),
                    );
                  },
                ),
            },
            switch (socialFollowing.twitchHandle) {
              None() => null,
              Some(:final value) => _socialMediaIcon(
                  color: Colors.purple,
                  icon: const Icon(
                    FontAwesomeIcons.twitch,
                    color: Colors.purple,
                  ),
                  onTap: () {
                    launchUrl(
                      Uri(
                        scheme: 'https',
                        path: 'twitch.tv/$value',
                      ),
                    );
                  },
                ),
            },
            switch (socialFollowing.audiusHandle) {
              None() => null,
              Some(:final value) => _socialMediaIcon(
                  color: Colors.purpleAccent,
                  icon: SvgPicture.asset(
                    'assets/audius_logo.svg',
                    colorFilter:
                        const ColorFilter.mode(Colors.purple, BlendMode.srcIn),
                    semanticsLabel: 'Audius Logo',
                  ),
                  onTap: () {
                    launchUrl(
                      Uri(
                        scheme: 'https',
                        path: 'audius.co/$value',
                      ),
                    );
                  },
                ),
            },
          ].where((element) => element != null).whereType<Widget>().toList(),
          ),
        );
      },
    );
  }
}
