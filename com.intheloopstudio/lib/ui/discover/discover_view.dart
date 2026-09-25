import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/data/search_repository.dart';
import 'package:intheloopapp/domains/models/genre.dart';
import 'package:intheloopapp/domains/models/performer_info.dart';
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/domains/onboarding_bloc/onboarding_bloc.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/design/premium_banner.dart';
import 'package:intheloopapp/ui/discover/components/draggable_sheet.dart';
import 'package:intheloopapp/ui/discover/components/map_base.dart';
import 'package:intheloopapp/ui/discover/components/map_settings.dart';
import 'package:intheloopapp/ui/discover/components/search_new_area_button.dart';
import 'package:intheloopapp/ui/discover/components/tapped_search_bar.dart';
import 'package:intheloopapp/ui/discover/discover_cubit.dart';
import 'package:intheloopapp/ui/tasks/components/tasks_banner.dart';
import 'package:intheloopapp/ui/user_avatar.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:intheloopapp/utils/current_user_builder.dart';
import 'package:intheloopapp/utils/premium_builder.dart';
import 'package:latlong2/latlong.dart';
import 'package:stream_chat_flutter/stream_chat_flutter.dart';

/// The home surface. Map edge-to-edge, glass chrome floating above it,
/// results in a glass sheet that lifts from the bottom — the same model as
/// Apple Maps.
class DiscoverView extends StatelessWidget {
  const DiscoverView({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final mapController = MapController();
    return CurrentUserBuilder(
      builder: (context, currentUser) {
        return PremiumBuilder(
          builder: (context, isPremium) {
            final initGenres = isPremium
                ? currentUser.performerInfo
                      .map((info) => info.genres)
                      .getOrElse(() => [])
                : <String>[];
            return BlocProvider<DiscoverCubit>(
              create: (context) => DiscoverCubit(
                currentUser: currentUser,
                database: context.database,
                search: context.read<SearchRepository>(),
                initGenres: fromStrings(initGenres),
                onboardingBloc: context.read<OnboardingBloc>(),
                places: context.places,
                suggestedMaxCapacity: isPremium
                    ? currentUser.performerInfo
                          .map((info) => info.category.suggestedMaxCapacity)
                          .getOrElse(() => 1000)
                    : 1000,
              ),
              child: Scaffold(
                extendBody: true,
                extendBodyBehindAppBar: true,
                body: Stack(
                  fit: StackFit.expand,
                  children: [
                    MapBase(mapController: mapController),
                    _MapControls(mapController: mapController),
                    _TopChrome(currentUser: currentUser),
                  ],
                ),
                bottomSheet: DraggableSheet(),
              ),
            );
          },
        );
      },
    );
  }
}

class _TopChrome extends StatelessWidget {
  const _TopChrome({required this.currentUser});

  final UserModel currentUser;

  @override
  Widget build(BuildContext context) {
    final streamClient = StreamChat.of(context).client;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          GlassMetrics.edgeInset,
          TappedSpacing.sm,
          GlassMetrics.edgeInset,
          0,
        ),
        child: Column(
          children: [
            Row(
              children: [
                LiquidGlass.circle(
                  width: GlassMetrics.control,
                  height: GlassMetrics.control,
                  padding: const EdgeInsets.all(3),
                  child: UserAvatar(
                    radius: 22,
                    imageUrl: currentUser.profilePicture,
                    pushUser: Option.of(currentUser),
                    pushId: Option.of(currentUser.id),
                  ),
                ),
                const SizedBox(width: TappedSpacing.sm),
                const Expanded(child: TappedSearchBar()),
                const SizedBox(width: TappedSpacing.sm),
                StreamBuilder<int?>(
                  stream: streamClient
                      .on()
                      .where((event) => event.totalUnreadCount != null)
                      .map((event) => event.totalUnreadCount),
                  initialData: streamClient.state.totalUnreadCount,
                  builder: (context, snapshot) {
                    final unread = snapshot.data ?? 0;
                    return GlassIconButton(
                      icon: CupertinoIcons.bubble_left_bubble_right_fill,
                      size: GlassMetrics.control,
                      badge: unread,
                      semanticsLabel: 'messages',
                      onPressed: () => context.push(MessagingChannelListPage()),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: TappedSpacing.md),
            const _OverlaySwitcher(),
            const SizedBox(height: TappedSpacing.xs),
            const PremiumBanner(),
            const TasksBanner(),
            const SearchNewAreaButton(),
          ],
        ),
      ),
    );
  }
}

/// venues / gigs toggle, a native segmented control rather than a hidden
/// layers picker.
class _OverlaySwitcher extends StatelessWidget {
  const _OverlaySwitcher();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DiscoverCubit, DiscoverState>(
      buildWhen: (a, b) => a.mapOverlay != b.mapOverlay,
      builder: (context, state) {
        return Center(
          child: SizedBox(
            width: 220,
            child: GlassSegmentedControl<MapOverlay>(
              selected: state.mapOverlay,
              onChanged: context.read<DiscoverCubit>().onMapOverlayChange,
              segments: const {
                MapOverlay.venues: GlassSegment(
                  label: 'venues',
                  icon: CupertinoIcons.building_2_fill,
                ),
                MapOverlay.opportunities: GlassSegment(
                  label: 'gigs',
                  icon: CupertinoIcons.music_mic,
                ),
              },
            ),
          ),
        );
      },
    );
  }
}

/// Vertical stack of clear-glass map controls (filters, locate, debug zoom)
/// pinned above the sheet on the trailing edge.
class _MapControls extends StatelessWidget {
  const _MapControls({required this.mapController});

  final MapController mapController;

  @override
  Widget build(BuildContext context) {
    return PremiumBuilder(
      builder: (context, isPremium) {
        return BlocBuilder<DiscoverCubit, DiscoverState>(
          builder: (context, state) {
            final cubit = context.read<DiscoverCubit>();
            final hasFilters = state.genreFilters.isNotEmpty;
            return Positioned(
              bottom: 132,
              right: GlassMetrics.edgeInset,
              child: LiquidGlass.capsule(
                variant: GlassVariant.clear,
                padding: const EdgeInsets.all(4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (state.mapOverlay == MapOverlay.venues)
                      _ControlButton(
                        icon: CupertinoIcons.slider_horizontal_3,
                        active: hasFilters,
                        label: 'filters',
                        onPressed: () => showGlassSheet<void>(
                          context: context,
                          title: 'filters',
                          showClose: true,
                          scrollable: true,
                          builder: (ctx) => MapSettings(
                            genreFilters: isPremium ? state.genreFilters : [],
                            onConfirmGenreSelection: (genres) {
                              if (!isPremium) {
                                context.push(PaywallPage());
                                return;
                              }
                              cubit.setGenreFilters(
                                genres.whereType<Genre>().toList(),
                              );
                            },
                            initialRange: isPremium
                                ? state.capacityRange
                                : null,
                            maxCapacity: state.capacityRange.end.round() < 1000
                                ? 1000
                                : state.capacityRange.end.round(),
                            onCapacityRangeChange: (ranges) {
                              if (!isPremium) {
                                context.push(PaywallPage());
                                return;
                              }
                              cubit.updateCapacityRange(ranges);
                            },
                          ),
                        ),
                      ),
                    _ControlButton(
                      icon: CupertinoIcons.location_fill,
                      label: 'my location',
                      onPressed: () {
                        FirebaseAnalytics.instance.logEvent(
                          name: 'discover_seek_home',
                        );
                        mapController.move(
                          LatLng(state.userLat, state.userLng),
                          13,
                        );
                      },
                    ),
                    if (kDebugMode) ...[
                      _ControlButton(
                        icon: CupertinoIcons.plus,
                        label: 'zoom in',
                        onPressed: () => mapController.move(
                          mapController.camera.center,
                          mapController.camera.zoom + 1,
                        ),
                      ),
                      _ControlButton(
                        icon: CupertinoIcons.minus,
                        label: 'zoom out',
                        onPressed: () => mapController.move(
                          mapController.camera.center,
                          mapController.camera.zoom - 1,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.onPressed,
    required this.label,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassPressable(
      onPressed: onPressed,
      semanticsLabel: label,
      child: SizedBox(
        width: GlassMetrics.iconControl,
        height: GlassMetrics.iconControl,
        child: Center(
          child: Icon(
            icon,
            size: 20,
            color: active
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
