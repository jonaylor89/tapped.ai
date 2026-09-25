import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/domains/models/spotify_track.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/profile/profile_cubit.dart';
import 'package:intheloopapp/utils/default_image.dart';
import 'package:url_launcher/url_launcher.dart';

/// Album-art rail of a performer's top Spotify tracks.
class TopTracksSliver extends StatelessWidget {
  const TopTracksSliver({super.key});

  Widget _buildTrack(SpotifyTrack track) {
    final trackImage = track.album
        .map((album) => album.images)
        .getOrElse(() => [])
        .firstOrNull;

    final imageProvider = trackImage != null
        ? CachedNetworkImageProvider(trackImage.url)
        : getDefaultImage(Option.of(track.id));

    final spotifyLink = track.externalUrls
        .map((urls) => urls['spotify'] as String?)
        .toNullable();

    return GlassImageCard(
      image: imageProvider,
      width: 150,
      height: 150,
      semanticsLabel: 'open ${track.name} on spotify',
      topRight: const LiquidGlass.circle(
        width: 32,
        height: 32,
        tint: Color(0xFF1DB954),
        child: Center(
          child: Icon(
            CupertinoIcons.play_fill,
            color: Colors.white,
            size: 14,
          ),
        ),
      ),
      onTap: spotifyLink == null
          ? null
          : () => launchUrl(Uri.parse(spotifyLink)),
      child: Text(
        track.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          height: 1.15,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        if (state.topTracks.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const GlassSectionTitle('top tracks'),
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: GlassMetrics.edgeInset,
                ),
                itemCount: state.topTracks.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: TappedSpacing.sm),
                itemBuilder: (context, i) => _buildTrack(state.topTracks[i]),
              ),
            ),
          ],
        );
      },
    );
  }
}
