import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:formz/formz.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:intheloopapp/domains/models/spotify_artist.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/forms/spotify_text_field.dart';
import 'package:intheloopapp/utils/app_logger.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:url_launcher/url_launcher.dart';

class OnboardWithSpotifyView extends StatefulWidget {
  const OnboardWithSpotifyView({
    this.initialValue,
    this.onChanged,
    super.key,
  });

  final String? initialValue;
  final void Function(SpotifyArtist)? onChanged;

  @override
  State<OnboardWithSpotifyView> createState() => _OnboardWithSpotifyViewState();
}

class _OnboardWithSpotifyViewState extends State<OnboardWithSpotifyView> {
  FormzSubmissionStatus _status = FormzSubmissionStatus.initial;
  Option<SpotifyArtist> _spotifyArtist = const None();
  late String _spotifyUrl;

  @override
  void initState() {
    _spotifyUrl = widget.initialValue ?? '';
    super.initState();
  }

  Future<void> _fetch() async {
    final spotify = context.spotify;
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_spotifyUrl.isEmpty) {
        throw Exception("spotify url can't be empty");
      }

      final uri = Uri.tryParse(_spotifyUrl);
      if (uri == null) {
        throw Exception("url isn't formatted correctly");
      }

      final spotifyId = uri.pathSegments.lastOrNull;
      if (spotifyId == null) {
        throw Exception("url isn't formatted correctly");
      }

      setState(() {
        _status = FormzSubmissionStatus.inProgress;
      });

      final res = await spotify.getArtistById(spotifyId);

      switch (res) {
        case None():
          setState(() {
            _status = FormzSubmissionStatus.failure;
          });
        case Some(:final value):
          setState(() {
            _spotifyArtist = Option.of(value);
            _status = FormzSubmissionStatus.success;
          });
      }
    } catch (e, s) {
      logger.e(
        'error fetching spotify',
        error: e,
        stackTrace: s,
      );
      setState(() {
        _status = FormzSubmissionStatus.failure;
      });
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(e.toString()),
        ),
      );
    }
  }

  Widget _shell({required List<Widget> children, Widget? bottom}) {
    return GlassAmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              GlassMetrics.edgeInset,
              TappedSpacing.md,
              GlassMetrics.edgeInset,
              TappedSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: GlassGrabber()),
                const SizedBox(height: TappedSpacing.xl),
                ...children,
                if (bottom != null) ...[
                  const Spacer(),
                  bottom,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cancel() {
    return GlassButton.plain(
      label: 'cancel',
      expand: true,
      onPressed: () => Navigator.pop(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    return switch (_status) {
      FormzSubmissionStatus.failure || FormzSubmissionStatus.canceled => _shell(
        children: [
          GlassEmptyState(
            icon: CupertinoIcons.exclamationmark_triangle,
            title: "couldn't reach spotify",
            message: 'double-check the artist url and try again',
            actionLabel: 'try again',
            onAction: () => setState(() {
              _status = FormzSubmissionStatus.initial;
            }),
          ),
        ],
        bottom: _cancel(),
      ),
      FormzSubmissionStatus.inProgress => _shell(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(GlassRadius.sheet),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const Image(
                    image: AssetImage('assets/edm_loop.gif'),
                    fit: BoxFit.cover,
                  ),
                  Center(
                    child: LiquidGlass(
                      padding: const EdgeInsets.symmetric(
                        horizontal: TappedSpacing.xl,
                        vertical: TappedSpacing.lg,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CupertinoActivityIndicator(
                            color: Colors.white,
                          ),
                          const SizedBox(width: TappedSpacing.md),
                          Text(
                            'fetching your info from spotify…',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
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
        ],
      ),
      FormzSubmissionStatus.success => switch (_spotifyArtist) {
        None() => _shell(
          children: const [
            GlassEmptyState(
              icon: CupertinoIcons.exclamationmark_triangle,
              title: 'something went wrong',
            ),
          ],
          bottom: _cancel(),
        ),
        Some(:final value) => _shell(
          children: [
            const SizedBox(height: TappedSpacing.xl),
            Center(
              child: LiquidGlass.circle(
                width: 200,
                height: 200,
                padding: const EdgeInsets.all(6),
                child: ClipOval(
                  child: value.images.isNotEmpty
                      ? Image(
                          image: CachedNetworkImageProvider(
                            value.images.first.url,
                          ),
                          fit: BoxFit.cover,
                        )
                      : Icon(
                          CupertinoIcons.music_mic,
                          size: 64,
                          color: muted,
                        ),
                ),
              ),
            ),
            const SizedBox(height: TappedSpacing.xl),
            Text(
              value.name.getOrElse(() => 'artist name unknown'),
              textAlign: TextAlign.center,
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: TappedSpacing.sm),
            Text(
              'is this you?',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: muted),
            ),
            if (value.genres.isNotEmpty) ...[
              const SizedBox(height: TappedSpacing.lg),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: TappedSpacing.sm,
                runSpacing: TappedSpacing.sm,
                children: [
                  for (final genre in value.genres) GlassPill(label: genre),
                ],
              ),
            ],
          ],
          bottom: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassButton.primary(
                label: "yes, that's me",
                icon: CupertinoIcons.checkmark,
                expand: true,
                onPressed: () {
                  widget.onChanged?.call(value);
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: TappedSpacing.sm),
              _cancel(),
            ],
          ),
        ),
      },
      FormzSubmissionStatus.initial => _shell(
        children: [
          Text(
            'import from Spotify',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: TappedSpacing.xs),
          Text(
            "paste your artist page url and we'll pull your name, photo "
            'and genres',
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          ),
          const SizedBox(height: TappedSpacing.xl),
          SpotifyTextField(
            initialValue: widget.initialValue,
            onChanged: (value) => setState(() {
              _spotifyUrl = value;
            }),
          ),
          const SizedBox(height: TappedSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: GlassButton.plain(
              label: 'how do I find my spotify artist url?',
              icon: CupertinoIcons.question_circle,
              compact: true,
              onPressed: () => launchUrl(
                Uri.parse(
                  'https://tappedapp.notion.site/how-do-i-get-my-spotify-url-2d1250547a044071becbe43763a77583',
                ),
              ),
            ),
          ),
        ],
        bottom: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GlassButton.primary(
              label: 'look me up',
              icon: CupertinoIcons.search,
              expand: true,
              onPressed: _fetch,
            ),
            const SizedBox(height: TappedSpacing.sm),
            _cancel(),
          ],
        ),
      ),
    };
  }
}
