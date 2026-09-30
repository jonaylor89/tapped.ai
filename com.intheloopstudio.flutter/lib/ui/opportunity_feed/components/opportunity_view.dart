import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/data/places_repository.dart';
import 'package:intheloopapp/domains/models/booking.dart';
import 'package:intheloopapp/domains/models/opportunity.dart';
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/domains/opportunity_bloc/opportunity_bloc.dart';
import 'package:intheloopapp/ui/conditional_parent_widget.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/discover/components/user_slider.dart';
import 'package:intheloopapp/ui/opportunities/interested_users_view.dart';
import 'package:intheloopapp/ui/profile/profile_view.dart';
import 'package:intheloopapp/ui/user_avatar.dart';
import 'package:intheloopapp/ui/user_tile.dart';
import 'package:intheloopapp/utils/admin_builder.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:intheloopapp/utils/current_user_builder.dart';
import 'package:intheloopapp/utils/geohash.dart';
import 'package:intheloopapp/utils/hero_image.dart';
import 'package:intheloopapp/utils/opportunity_image.dart';
import 'package:intl/intl.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:share_plus/share_plus.dart';

/// Immersive opportunity detail: full-bleed flier with glass chrome floating
/// over it, then grouped facts, description, lineup and booker below.
class OpportunityView extends StatelessWidget {
  const OpportunityView({
    required this.opportunityId,
    required this.opportunity,
    this.isApplied,
    this.onApply,
    this.onDislike,
    this.onDismiss,
    this.heroImage,
    this.titleHeroTag,
    this.showAppBar = true,
    this.showDislikeButton = true,
    super.key,
  });

  final String opportunityId;
  final Option<Opportunity> opportunity;
  final bool? isApplied;
  final bool showDislikeButton;
  final bool showAppBar;
  final HeroImage? heroImage;
  final String? titleHeroTag;
  final void Function()? onApply;
  final void Function()? onDislike;
  final void Function()? onDismiss;

  static const _heroHeight = 420.0;

  Widget _flier(ImageProvider provider) => Image(
    image: provider,
    height: _heroHeight,
    width: double.infinity,
    fit: BoxFit.cover,
  );

  Widget _hero(BuildContext context, Opportunity op) {
    final hero = heroImage;
    final Widget image;
    if (hero == null) {
      image = FutureBuilder<ImageProvider>(
        future: getOpImage(context, op),
        builder: (context, snapshot) {
          final provider = snapshot.data;
          if (provider == null) {
            return const SizedBox(
              height: _heroHeight,
              width: double.infinity,
              child: GlassLoading(),
            );
          }
          return _flier(provider);
        },
      );
    } else {
      image = GestureDetector(
        onTap: () => context.push(ImagePage(heroImage: hero)),
        child: Hero(
          tag: hero.heroTag,
          child: _flier(hero.imageProvider),
        ),
      );
    }

    final theme = Theme.of(context);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        image,
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, 0.55, 1],
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    theme.colorScheme.surface,
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _title(BuildContext context, Opportunity op) {
    final theme = Theme.of(context);
    return ConditionalParentWidget(
      condition: titleHeroTag != null,
      conditionalBuilder: ({required child}) => Hero(
        tag: titleHeroTag!,
        child: child,
      ),
      child: Text(
        op.title,
        style: theme.textTheme.headlineMedium?.copyWith(
          fontFamily: 'Rubik One',
          fontWeight: FontWeight.w900,
          letterSpacing: -0.5,
        ),
      ),
    );
  }

  Widget _facts(
    BuildContext context, {
    required Opportunity op,
    required bool isAdmin,
  }) {
    final theme = Theme.of(context);
    final places = context.places;
    final database = context.database;
    return GlassSection(
      margin: EdgeInsets.zero,
      children: [
        switch (op.venueId) {
          None() => FutureBuilder<Option<PlaceData>>(
            future: places.getPlaceById(op.location.placeId),
            builder: (context, snapshot) {
              final placeData = snapshot.data;
              return switch (placeData) {
                null => const GlassListTile(
                  leadingIcon: CupertinoIcons.location_fill,
                  title: 'locating…',
                  showChevron: false,
                ),
                None() => const SizedBox.shrink(),
                Some(:final value) => GlassListTile(
                  leadingIcon: CupertinoIcons.location_fill,
                  leadingColor: TappedColors.accent,
                  title: formattedShortAddress(value.addressComponents),
                  showChevron: false,
                ),
              };
            },
          ),
          Some(:final value) => FutureBuilder<Option<UserModel>>(
            future: database.getUserById(value),
            builder: (context, snapshot) {
              final venue = snapshot.data;
              return switch (venue) {
                null => const GlassListTile(
                  leadingIcon: CupertinoIcons.building_2_fill,
                  title: 'loading venue…',
                  showChevron: false,
                ),
                None() => const SizedBox.shrink(),
                Some(:final value) => GlassListTile(
                  leading: UserAvatar(
                    pushId: Option.of(value.id),
                    pushUser: Option.of(value),
                    imageUrl: value.profilePicture,
                    radius: 16,
                  ),
                  title: value.displayName,
                  subtitle: 'venue',
                  onTap: () => showCupertinoModalBottomSheet<void>(
                    context: context,
                    builder: (context) => ProfileView(
                      visitedUserId: value.id,
                      visitedUser: Option.of(value),
                    ),
                  ),
                ),
              };
            },
          ),
        },
        GlassListTile(
          leadingIcon: CupertinoIcons.calendar,
          leadingColor: TappedColors.warning,
          title: DateFormat('EEEE, MMM d').format(op.startTime),
          subtitle: DateFormat.jm().format(op.startTime),
          showChevron: false,
        ),
        GlassListTile(
          leadingIcon: CupertinoIcons.money_dollar_circle_fill,
          leadingColor: op.isPaid ? TappedColors.success : TappedColors.error,
          title: op.isPaid ? 'paid gig' : 'unpaid',
          showChevron: false,
        ),
        if (isAdmin)
          GlassListTile(
            leadingIcon: CupertinoIcons.link,
            title: op.id,
            subtitle: 'tap to copy',
            showChevron: false,
            onTap: () {
              Clipboard.setData(ClipboardData(text: op.id));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(GlassRadius.control),
                  ),
                  content: const Text('copied to clipboard'),
                ),
              );
            },
          ),
        if (op.description.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              GlassMetrics.edgeInset,
              TappedSpacing.md,
              GlassMetrics.edgeInset,
              GlassMetrics.edgeInset,
            ),
            child: Text(
              op.description,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ),
      ],
    );
  }

  Widget _lineup(BuildContext context, Opportunity op) {
    final theme = Theme.of(context);
    final database = context.database;
    return switch (op.referenceEventId) {
      None() => const SizedBox.shrink(),
      Some(:final value) => FutureBuilder<List<Booking>>(
        future: database.getBookingsByEventId(value),
        builder: (context, snapshot) {
          final bookings = snapshot.data;
          if (bookings == null || bookings.isEmpty) {
            return const SizedBox.shrink();
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const GlassSectionTitle('current lineup'),
              FutureBuilder(
                future: Future.wait(
                  bookings.map(
                    (booking) => database.getUserById(booking.requesteeId),
                  ),
                ),
                builder: (context, snapshot) {
                  final users = snapshot.data;
                  if (users == null) {
                    return const GlassLoading();
                  }

                  final realUsers = users
                      .whereType<Some<UserModel>>()
                      .map((user) => user.value)
                      .toList();

                  if (realUsers.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: GlassMetrics.edgeInset,
                      ),
                      child: Text(
                        'empty bill',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                    );
                  }

                  return UserSlider(users: realUsers);
                },
              ),
            ],
          );
        },
      ),
    };
  }

  Widget _actions(
    BuildContext context, {
    required Opportunity op,
    required bool? isApplied,
    required UserModel currentUser,
    required bool isAdmin,
  }) {
    final opBloc = context.opportunities;
    final isOwner = op.userId == currentUser.id;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            GlassIconButton(
              icon: CupertinoIcons.share,
              semanticsLabel: 'share opportunity',
              onPressed: () {
                Share.share('https://app.tapped.ai/opportunity/${op.id}');
              },
            ),
            if (!isOwner && showDislikeButton && isApplied == false) ...[
              const SizedBox(width: TappedSpacing.sm),
              GlassIconButton(
                icon: CupertinoIcons.hand_thumbsdown,
                semanticsLabel: 'not interested',
                onPressed: () {
                  opBloc.add(DislikeOpportunity(opportunity: op));
                  onDislike?.call();
                },
              ),
            ],
            const SizedBox(width: TappedSpacing.sm),
            Expanded(
              child: switch ((isOwner || isAdmin, isApplied)) {
                (true, _) => GlassButton.primary(
                  label: 'see applicants',
                  icon: CupertinoIcons.person_2_fill,
                  expand: true,
                  onPressed: () => showCupertinoModalBottomSheet<void>(
                    context: context,
                    builder: (context) => InterestedUsersView(opportunity: op),
                  ),
                ),
                (false, null) => const GlassButton.primary(
                  label: 'checking…',
                  expand: true,
                  onPressed: null,
                ),
                (false, false) => GlassButton.primary(
                  label: 'apply',
                  icon: CupertinoIcons.paperplane_fill,
                  expand: true,
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    final quota = opBloc.state.opQuota;
                    opBloc.add(
                      ApplyForOpportunity(
                        opportunity: op,
                        userComment: '',
                      ),
                    );
                    if (quota > 0) {
                      onApply?.call();
                    }
                  },
                ),
                (false, true) => const GlassButton(
                  label: 'applied',
                  icon: CupertinoIcons.checkmark_seal_fill,
                  expand: true,
                  onPressed: null,
                ),
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget buildOpportunityView(
    BuildContext context, {
    required Opportunity op,
    required bool? isApplied,
    required UserModel currentUser,
  }) {
    return AdminBuilder(
      builder: (context, isAdmin) {
        return GlassAmbientBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            extendBodyBehindAppBar: true,
            body: Stack(
              children: [
                CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(child: _hero(context, op)),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: GlassMetrics.edgeInset,
                      ),
                      sliver: SliverList.list(
                        children: [
                          _title(context, op),
                          const SizedBox(height: TappedSpacing.lg),
                          _facts(context, op: op, isAdmin: isAdmin),
                        ],
                      ),
                    ),
                    SliverToBoxAdapter(child: _lineup(context, op)),
                    const SliverToBoxAdapter(
                      child: GlassSectionTitle('booker'),
                    ),
                    SliverToBoxAdapter(
                      child: GlassSection(
                        children: [
                          UserTile(userId: op.userId, user: const None()),
                        ],
                      ),
                    ),
                    const SliverToBoxAdapter(
                      child: SizedBox(
                        height: GlassMetrics.bottomBarClearance + 24,
                      ),
                    ),
                  ],
                ),
                if (showAppBar)
                  Positioned(
                    top: MediaQuery.paddingOf(context).top + TappedSpacing.sm,
                    left: GlassMetrics.edgeInset,
                    child: GlassIconButton(
                      icon: CupertinoIcons.chevron_back,
                      semanticsLabel: 'back',
                      variant: GlassVariant.clear,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: GlassBottomBar(
                    child: _actions(
                      context,
                      op: op,
                      isApplied: isApplied,
                      currentUser: currentUser,
                      isAdmin: isAdmin,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final database = context.database;
    return CurrentUserBuilder(
      builder: (context, currentUser) {
        return FutureBuilder(
          future: isApplied == null
              ? database.isUserAppliedForOpportunity(
                  opportunityId: opportunityId,
                  userId: currentUser.id,
                )
              : Future<bool>.value(isApplied),
          builder: (context, snapshot) {
            final isApplied = snapshot.data;
            return switch (opportunity) {
              None() => FutureBuilder<Option<Opportunity>>(
                future: database.getOpportunityById(opportunityId),
                builder: (context, snapshot) {
                  final op = snapshot.data;
                  return switch (op) {
                    null => const GlassAmbientBackground(
                      child: GlassLoading(),
                    ),
                    None() => const GlassAmbientBackground(
                      child: GlassEmptyState(
                        icon: CupertinoIcons.exclamationmark_triangle,
                        title: 'opportunity not found',
                        message: 'it may have been removed',
                      ),
                    ),
                    Some(:final value) => buildOpportunityView(
                      context,
                      op: value,
                      isApplied: isApplied,
                      currentUser: currentUser,
                    ),
                  };
                },
              ),
              Some(:final value) => buildOpportunityView(
                context,
                op: value,
                isApplied: isApplied,
                currentUser: currentUser,
              ),
            };
          },
        );
      },
    );
  }
}
