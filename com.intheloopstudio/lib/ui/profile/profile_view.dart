import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/data/database_repository.dart';
import 'package:intheloopapp/data/places_repository.dart';
import 'package:intheloopapp/data/spotify_repository.dart';
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/domains/models/venue_info.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/domains/onboarding_bloc/onboarding_bloc.dart';
import 'package:intheloopapp/ui/conditional_parent_widget.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/error/error_view.dart';
import 'package:intheloopapp/ui/loading/loading_view.dart';
import 'package:intheloopapp/ui/profile/components/bio_sliver.dart';
import 'package:intheloopapp/ui/profile/components/booking_controls_sliver.dart';
import 'package:intheloopapp/ui/profile/components/bookings_sliver.dart';
import 'package:intheloopapp/ui/profile/components/claim_profile_button.dart';
import 'package:intheloopapp/ui/profile/components/header_sliver.dart';
import 'package:intheloopapp/ui/profile/components/info_sliver.dart';
import 'package:intheloopapp/ui/profile/components/more_options_button.dart';
import 'package:intheloopapp/ui/profile/components/opportunities_sliver.dart';
import 'package:intheloopapp/ui/profile/components/reviews_sliver.dart';
import 'package:intheloopapp/ui/profile/components/social_media_icons.dart';
import 'package:intheloopapp/ui/profile/components/top_performers_sliver.dart';
import 'package:intheloopapp/ui/profile/components/top_tracks_sliver.dart';
import 'package:intheloopapp/ui/profile/profile_cubit.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:intheloopapp/utils/default_image.dart';
import 'package:intheloopapp/utils/geohash.dart';
import 'package:intheloopapp/utils/hero_image.dart';

/// Native-feeling profile: a full-bleed hero that stretches on pull, floating
/// glass controls that stay put, and content that reads as inset grouped
/// glass cards over an ambient background.
class ProfileView extends StatelessWidget {
  ProfileView({
    required this.visitedUserId,
    required this.visitedUser,
    this.heroImage,
    this.titleHeroTag,
    this.onQuit,
    this.collapsedBarHeight = 60.0,
    this.expandedBarHeight = 380.0,
    this.stretchable = false,
    super.key,
    ScrollController? scrollController,
  }) : scrollController = scrollController ?? ScrollController();

  final String visitedUserId;
  final double collapsedBarHeight;
  final double expandedBarHeight;
  final bool stretchable;
  final HeroImage? heroImage;
  final String? titleHeroTag;
  final void Function()? onQuit;
  final ScrollController scrollController;

  // callers can provide a user to avoid a database call
  final Option<UserModel> visitedUser;

  ImageProvider _getProfileImage(String? profilePicture) {
    return (profilePicture == null)
        ? getDefaultImage(Option.of(visitedUserId))
        : CachedNetworkImageProvider(
            profilePicture,
          );
  }

  Widget _profileImage(BuildContext context, String? profilePicture) {
    final hero = heroImage;
    final imageProvider = _getProfileImage(profilePicture);
    final surface = Theme.of(context).colorScheme.surface;
    return ConditionalParentWidget(
      condition: hero != null,
      conditionalBuilder: ({required child}) {
        return Hero(
          tag: hero!.heroTag,
          child: child,
        );
      },
      child: GestureDetector(
        onTap: () => context.push(
          ImagePage(
            heroImage:
                heroImage ??
                HeroImage(
                  heroTag: titleHeroTag ?? visitedUserId,
                  imageProvider: imageProvider,
                ),
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image(image: imageProvider, fit: BoxFit.cover),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, 0.35, 0.75, 1],
                  colors: [
                    Colors.black.withValues(alpha: 0.35),
                    Colors.transparent,
                    surface.withValues(alpha: 0.55),
                    surface,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profilePage(
    UserModel currentUser,
    UserModel visitedUser,
    DatabaseRepository databaseRepository,
    PlacesRepository places,
    SpotifyRepository spotify,
  ) => BlocProvider(
    create: (context) =>
        ProfileCubit(
            spotify: spotify,
            places: places,
            database: databaseRepository,
            currentUser: currentUser,
            visitedUser: visitedUser,
          )
          ..getTopBookings()
          ..getLatestReview()
          ..initOpportunities()
          ..initTopSpotifyTracks()
          ..loadIsBlocked()
          ..loadIsVerified(visitedUser.id)
          ..initPlace(),
    child: BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        return BlocListener<OnboardingBloc, OnboardingState>(
          listener: (context, userState) {
            if (userState is Onboarded) {
              if (userState.currentUser.id == visitedUser.id) {
                context.read<ProfileCubit>().refetchVisitedUser(
                  newUserData: userState.currentUser,
                );
              }
            }
          },
          child: ConditionalParentWidget(
            condition: stretchable,
            conditionalBuilder: ({required child}) {
              return NotificationListener<ScrollNotification>(
                onNotification: (notification) =>
                    context.read<ProfileCubit>().onNotification(
                      scrollController,
                      expandedBarHeight,
                      collapsedBarHeight,
                    ),
                child: child,
              );
            },
            child: GlassAmbientBackground(
              child: CustomScrollView(
                controller: scrollController,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                slivers: [
                  _heroSliver(context, state, visitedUser),
                  if (state.isBlocked)
                    ..._blockedSlivers(context)
                  else
                    ..._unblockedSlivers(context, state),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget _heroSliver(
    BuildContext context,
    ProfileState state,
    UserModel visitedUser,
  ) {
    final theme = Theme.of(context);
    final topPadding = MediaQuery.paddingOf(context).top;
    return SliverAppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      expandedHeight: expandedBarHeight,
      collapsedHeight: collapsedBarHeight,
      toolbarHeight: collapsedBarHeight,
      automaticallyImplyLeading: false,
      pinned: true,
      stretch: stretchable,
      onStretchTrigger: stretchable
          ? () async {
              final cubit = context.read<ProfileCubit>();
              await Future.wait([
                HapticFeedback.mediumImpact(),
                cubit.getTopBookings(),
                cubit.getLatestReview(),
                cubit.initOpportunities(),
                cubit.initTopSpotifyTracks(),
                cubit.refetchVisitedUser(),
                cubit.loadIsVerified(visitedUser.id),
              ]);
            }
          : null,
      leading: Padding(
        padding: const EdgeInsets.only(left: GlassMetrics.edgeInset - 8),
        child: Center(
          child: GlassIconButton(
            icon: onQuit != null
                ? CupertinoIcons.xmark
                : CupertinoIcons.chevron_back,
            variant: GlassVariant.clear,
            semanticsLabel: 'close profile',
            onPressed: onQuit ?? () => context.pop(),
          ),
        ),
      ),
      leadingWidth: GlassMetrics.iconControl + GlassMetrics.edgeInset,
      actions: const [
        Padding(
          padding: EdgeInsets.only(right: GlassMetrics.edgeInset - 8),
          child: Center(child: MoreOptionsButton()),
        ),
      ],
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final collapsedExtent = collapsedBarHeight + topPadding;
          final t =
              ((constraints.maxHeight - collapsedExtent) /
                      (expandedBarHeight - collapsedBarHeight))
                  .clamp(0.0, 1.0);
          return Stack(
            fit: StackFit.expand,
            children: [
              FlexibleSpaceBar(
                stretchModes: const [StretchMode.zoomBackground],
                collapseMode: CollapseMode.parallax,
                background: _profileImage(
                  context,
                  visitedUser.profilePicture.toNullable(),
                ),
              ),
              // Inline glass title fades in as the hero collapses.
              Positioned(
                top: topPadding,
                left: 0,
                right: 0,
                height: collapsedBarHeight,
                child: IgnorePointer(
                  child: Center(
                    child: AnimatedOpacity(
                      duration: GlassMotion.press,
                      opacity: 1 - t,
                      child: LiquidGlass.capsule(
                        variant: GlassVariant.clear,
                        padding: const EdgeInsets.symmetric(
                          horizontal: TappedSpacing.md,
                          vertical: TappedSpacing.xs,
                        ),
                        child: Text(
                          visitedUser.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Large name + meta anchored to the bottom of the hero.
              Positioned(
                left: GlassMetrics.edgeInset,
                right: GlassMetrics.edgeInset,
                bottom: TappedSpacing.sm,
                child: Opacity(
                  opacity: t,
                  child: _HeroTitle(state: state),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _unblockedSlivers(BuildContext context, ProfileState state) => [
    const SliverToBoxAdapter(child: HeaderSliver()),
    if (state.isCurrentUser)
      const SliverToBoxAdapter(child: BookingControlsSliver()),
    const SliverToBoxAdapter(child: InfoSliver()),
    const SocialMediaIcons(),
    const SliverToBoxAdapter(child: OpportunitiesSliver()),
    const SliverToBoxAdapter(child: TopPerformersSliver()),
    const SliverToBoxAdapter(child: TopTracksSliver()),
    const SliverToBoxAdapter(child: BookingsSliver()),
    const SliverToBoxAdapter(child: ReviewsSliver()),
    const SliverToBoxAdapter(child: BioSliver()),
    if (state.visitedUser.unclaimed)
      const SliverToBoxAdapter(child: ClaimProfileButton()),
    const SliverToBoxAdapter(
      child: SizedBox(height: GlassMetrics.bottomBarClearance),
    ),
  ];

  List<Widget> _blockedSlivers(BuildContext context) => [
    SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.all(GlassMetrics.edgeInset),
        child: GlassEmptyState(
          icon: CupertinoIcons.hand_raised_fill,
          title: 'blocked',
          message:
              'you blocked this user. they cannot see your '
              'profile or message you.',
          actionLabel: 'unblock',
          onAction: () => context.read<ProfileCubit>().unblock(),
        ),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final database = context.database;
    final places = context.places;
    final spotify = context.spotify;
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: BlocBuilder<OnboardingBloc, OnboardingState>(
        buildWhen: (previous, current) {
          if (previous is Onboarded && current is Onboarded) {
            return previous.currentUser.id != current.currentUser.id;
          }

          return true;
        },
        builder: (context, state) {
          final currentUser = (state is Onboarded) ? state.currentUser : null;
          if (currentUser == null) {
            return const ErrorView();
          }

          return switch ((visitedUser, currentUser.id == visitedUserId)) {
            (_, true) => _profilePage(
              currentUser,
              currentUser,
              database,
              places,
              spotify,
            ),
            (None(), false) => FutureBuilder<Option<UserModel>>(
              future: database.getUserById(visitedUserId),
              builder: (context, snapshot) {
                final user = snapshot.data;

                return switch (user) {
                  null => const LoadingView(),
                  None() => const LoadingView(),
                  Some(:final value) => _profilePage(
                    currentUser,
                    value,
                    database,
                    places,
                    spotify,
                  ),
                };
              },
            ),
            (Some(:final value), false) => _profilePage(
              currentUser,
              value,
              database,
              places,
              spotify,
            ),
          };
        },
      ),
    );
  }
}

class _HeroTitle extends StatelessWidget {
  const _HeroTitle({required this.state});

  final ProfileState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = state.visitedUser;
    final place = state.place.toNullable();
    final venueType = user.venueInfo
        .map((v) => v.type.formattedName.toLowerCase())
        .toNullable();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Text(
                user.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
            if (state.isVerified)
              Padding(
                padding: const EdgeInsets.only(
                  left: TappedSpacing.xs,
                  bottom: 6,
                ),
                child: GestureDetector(
                  onTap: () => _showVerified(context),
                  child: Icon(
                    CupertinoIcons.checkmark_seal_fill,
                    size: 22,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: TappedSpacing.sm),
        Wrap(
          spacing: TappedSpacing.xs,
          runSpacing: TappedSpacing.xs,
          children: [
            GlassPill(
              label: '@${user.username}',
              variant: GlassVariant.clear,
            ),
            if (venueType != null)
              GlassPill(
                label: venueType,
                icon: CupertinoIcons.building_2_fill,
                variant: GlassVariant.clear,
              ),
            if (place != null)
              GlassPill(
                label: formattedShortAddress(
                  place.addressComponents,
                ).toLowerCase(),
                icon: CupertinoIcons.location_solid,
                variant: GlassVariant.clear,
              ),
          ],
        ),
      ],
    );
  }

  void _showVerified(BuildContext context) {
    final theme = Theme.of(context);
    showGlassSheet<void>(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: TappedSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.checkmark_seal_fill,
              color: theme.colorScheme.primary,
              size: 72,
            ),
            const SizedBox(height: TappedSpacing.md),
            Text(
              '${state.visitedUser.displayName} is verified',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: TappedSpacing.sm),
            Text(
              'to get verified, post a screenshot of your profile to your '
              'instagram story and tag @tappedai',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
