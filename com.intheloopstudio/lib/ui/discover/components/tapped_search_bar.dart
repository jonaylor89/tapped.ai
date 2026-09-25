import 'package:cached_annotation/cached_annotation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:intheloopapp/data/database_repository.dart';
import 'package:intheloopapp/data/search_repository.dart';
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/domains/search_bloc/search_bloc.dart';
import 'package:intheloopapp/ui/common/opportunity_card.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/design/premium_banner.dart';
import 'package:intheloopapp/ui/loading/logo_wave.dart';
import 'package:intheloopapp/ui/user_tile.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:intheloopapp/utils/custom_claims_builder.dart';

class TappedSearchBar extends StatefulWidget {
  const TappedSearchBar({
    this.focusNode,
    this.controller,
    this.onChanged,
    this.onTap,
    this.trailing,
    super.key,
  });

  final FocusNode? focusNode;
  final SearchController? controller;
  final void Function(String)? onChanged;
  final void Function()? onTap;
  final List<Widget>? trailing;

  @override
  State<TappedSearchBar> createState() => _TappedSearchBarState();
}

class _TappedSearchBarState extends State<TappedSearchBar> {
  late final FocusNode _searchFocusNode;
  late final SearchController _searchController;
  late final ScrollController _scrollController = ScrollController();
  var _loadingSuggestions = true;

  void _search() {
    final query = _searchController.text;
    context.search.add(Search(query: query));
    widget.onChanged?.call(query);
  }

  @cached
  FutureOr<Iterable<Widget>> _getSuggestions({
    required DatabaseRepository database,
    required SearchRepository searchRepo,
  }) async {
    final [suggestedUsers, venuesNearby] = await Future.wait([
      database.getBookingLeaders(),
      searchRepo.queryUsers(
        '',
        occupations: ['Venue', 'venue'],
      ),
    ]);

    final featuredOps = await database.getFeaturedOpportunities();
    final sortedOps = featuredOps
      ..sort(
        (a, b) => a.startTime.compareTo(b.startTime),
      );

    final combined = [...suggestedUsers, ...venuesNearby]..sort(
        (a, b) => a.displayName.compareTo(b.displayName),
      );
    final combinedWidgets = combined.map(
      (user) => UserTile(
        userId: user.id,
        user: Option.of(user),
      ),
    );

    final featuredWidgets = sortedOps.map(
      (op) => OpportunityCard(opportunity: op),
    );

    return [...featuredWidgets, ...combinedWidgets];
  }

  @override
  void initState() {
    super.initState();
    _searchController = widget.controller ?? SearchController();
    _searchFocusNode = widget.focusNode ?? FocusNode();

    _searchController.addListener(_search);
  }

  @override
  void dispose() {
    super.dispose();
    _searchFocusNode.removeListener(_search);
    _searchController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final database = context.database;
    final searchRepo = context.read<SearchRepository>();
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.5);
    return SearchAnchor(
      searchController: _searchController,
      textCapitalization: TextCapitalization.none,
      textInputAction: TextInputAction.search,
      viewBackgroundColor: theme.colorScheme.surface,
      viewSurfaceTintColor: Colors.transparent,
      viewElevation: 0,
      viewHintText: 'search tapped',
      dividerColor: Colors.transparent,
      viewLeading: GlassIconButton(
        icon: CupertinoIcons.chevron_back,
        size: 36,
        iconSize: 18,
        onPressed: () {
          if (_searchController.isOpen) _searchController.closeView(null);
        },
        semanticsLabel: 'back',
      ),
      viewTrailing: [
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _searchController,
          builder: (context, value, _) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            return GlassIconButton(
              icon: CupertinoIcons.xmark,
              size: 32,
              iconSize: 14,
              onPressed: _searchController.clear,
              semanticsLabel: 'clear search',
            );
          },
        ),
      ],
      builder: (context, searchController) {
        return Hero(
          tag: 'searchBar',
          child: GlassSearchField(
            controller: searchController,
            readOnly: true,
            hintText: 'search tapped',
            onTap: () {
              searchController.openView();
              widget.onTap?.call();
            },
            trailing: widget.trailing != null && widget.trailing!.isNotEmpty
                ? Row(children: widget.trailing!)
                : CustomClaimsBuilder(
                    builder: (context, claims) {
                      final hasClaim = claims.isNotEmpty;
                      return GlassPressable(
                        haptics: false,
                        semanticsLabel: 'advanced search',
                        onPressed: () => switch (hasClaim) {
                          true => context.push(AdvancedSearchPage()),
                          false => context.push(PaywallPage()),
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(TappedSpacing.sm),
                          child: Icon(
                            CupertinoIcons.slider_horizontal_3,
                            size: 18,
                            color: muted,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        );
      },
      viewBuilder: (suggestions) {
        return BlocBuilder<SearchBloc, SearchState>(
          builder: (context, state) {
            if (_loadingSuggestions || state.loading) {
              return const Center(
                child: LogoWave(),
              );
            }

            if (suggestions.isNotEmpty && state.searchTerm.isEmpty) {
              final sugList = suggestions.toList();
              final ops = sugList.whereType<OpportunityCard>().toList();
              final restUsers = sugList.whereType<UserTile>();

              return GlassAmbientBackground(
                child: ListView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(
                    bottom: GlassMetrics.bottomBarClearance,
                  ),
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: GlassMetrics.edgeInset,
                      ),
                      child: PremiumBanner(),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        GlassMetrics.edgeInset,
                        TappedSpacing.sm,
                        GlassMetrics.edgeInset,
                        0,
                      ),
                      child: GlassButton(
                        label: 'search by city',
                        icon: CupertinoIcons.map,
                        expand: true,
                        onPressed: () => context.push(GigSearchPage()),
                      ),
                    ),
                    if (ops.isNotEmpty) ...[
                      const GlassSectionTitle('apply to perform'),
                      ...ops,
                    ],
                    if (restUsers.isNotEmpty) ...[
                      const GlassSectionTitle('suggested'),
                      ...restUsers,
                    ],
                  ],
                ),
              );
            }

            return GlassAmbientBackground(
              child: state.searchResults.isEmpty
                  ? const GlassEmptyState(
                      icon: CupertinoIcons.search,
                      title: 'nothing found',
                      message: 'try a different name or username',
                    )
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.only(
                        top: TappedSpacing.sm,
                        bottom: GlassMetrics.bottomBarClearance,
                      ),
                      itemCount: state.searchResults.length,
                      itemBuilder: (context, index) {
                        final user = state.searchResults[index];
                        return UserTile(
                          userId: user.id,
                          user: Option.of(user),
                        );
                      },
                    ),
            );
          },
        );
      },
      suggestionsBuilder: (context, searchController) async {
        if (searchController.text.isNotEmpty) {
          return const [];
        }

        final suggestions = await _getSuggestions(
          database: database,
          searchRepo: searchRepo,
        );

        setState(() {
          _loadingSuggestions = false;
        });

        return suggestions;
      },
    );
  }
}
