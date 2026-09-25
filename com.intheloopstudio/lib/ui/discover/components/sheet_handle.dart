import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/discover/discover_cubit.dart';

class SheetHandle extends StatelessWidget {
  const SheetHandle({
    required this.currentUser,
    required this.state,
    super.key,
  });

  final UserModel currentUser;
  final DiscoverState state;

  String _countLabel() {
    return switch (state.mapOverlay) {
      MapOverlay.venues => () {
          final n = state.venueHits.length;
          return '$n${n >= 75 ? '+' : ''} ${n == 1 ? 'venue' : 'venues'}';
        }(),
      MapOverlay.opportunities => () {
          final n = state.opportunityHits.length;
          return '$n${n >= 75 ? '+' : ''} ${n == 1 ? 'gig' : 'gigs'}';
        }(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const GlassGrabber(),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            GlassMetrics.edgeInset,
            TappedSpacing.md,
            GlassMetrics.edgeInset,
            TappedSpacing.lg,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_countLabel()} nearby',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (state.genreFilters.isNotEmpty)
                GlassPill(
                  icon: CupertinoIcons.slider_horizontal_3,
                  label: '${state.genreFilters.length} '
                      '${state.genreFilters.length == 1 ? 'genre' : 'genres'}',
                  tint: theme.colorScheme.primary,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
