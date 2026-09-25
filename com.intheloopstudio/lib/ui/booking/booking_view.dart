import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/data/database_repository.dart';
import 'package:intheloopapp/data/places_repository.dart';
import 'package:intheloopapp/domains/models/booking.dart';
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/profile/profile_view.dart';
import 'package:intheloopapp/ui/user_avatar.dart';
import 'package:intheloopapp/ui/user_tile.dart';
import 'package:intheloopapp/utils/admin_builder.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:intheloopapp/utils/current_user_builder.dart';
import 'package:intheloopapp/utils/default_image.dart';
import 'package:intheloopapp/utils/geohash.dart';
import 'package:intheloopapp/utils/hero_image.dart';
import 'package:intl/intl.dart';
import 'package:maps_launcher/maps_launcher.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';

class BookingView extends StatelessWidget {
  const BookingView({
    required this.booking,
    this.flierImage = const None(),
    this.onConfirm,
    this.onDeny,
    super.key,
  });

  final Booking booking;
  final Option<HeroImage> flierImage;
  final void Function(Booking)? onConfirm;
  final void Function(Booking)? onDeny;

  String get formattedDate {
    final outputFormat = DateFormat('MM/dd/yyyy');
    final outputDate = outputFormat.format(booking.startTime);
    return outputDate;
  }

  String formattedTime(DateTime time) {
    final outputFormat = DateFormat('HH:mm');
    final outputTime = outputFormat.format(time);
    return outputTime;
  }

  String formattedDuration(Duration d) {
    return d.toString().split('.').first.padLeft(8, '0');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final database = RepositoryProvider.of<DatabaseRepository>(context);
    return CurrentUserBuilder(
      builder: (context, currentUser) {
        final isCurrentUserInvolved = booking.requesterId.fold(
              () => false,
              (t) => t == currentUser.id,
            ) ||
            currentUser.id == booking.requesteeId;

        final imageProvider = flierImage.fold(
          () => booking.flierUrl.fold(
            () => getDefaultImage(const None()),
            (flierUrl) {
              if (flierUrl.isNotEmpty) {
                return CachedNetworkImageProvider(flierUrl);
              }
              return getDefaultImage(const None());
            },
          ),
          (flier) => flier.imageProvider,
        );
        final heroTag = flierImage.fold(
          () => booking.id,
          (flier) => flier.heroTag,
        );

        final timeFormat = DateFormat.jm();
        final dateFormat = DateFormat.yMMMMEEEEd();
        final canConfirm =
            booking.isPending && booking.requesteeId == currentUser.id;
        final canCancel = isCurrentUserInvolved &&
            !booking.isExpired &&
            !booking.isCanceled;

        return AdminBuilder(
          builder: (context, isAdmin) {
            final heroHeight = MediaQuery.sizeOf(context).height * 0.48;
            return Scaffold(
              backgroundColor: theme.colorScheme.surface,
              extendBody: true,
              body: Stack(
                children: [
                  CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      SliverAppBar(
                        expandedHeight: heroHeight,
                        pinned: true,
                        stretch: true,
                        backgroundColor: Colors.transparent,
                        automaticallyImplyLeading: false,
                        flexibleSpace: FlexibleSpaceBar(
                          stretchModes: const [StretchMode.zoomBackground],
                          background: GestureDetector(
                            onTap: () => context.push(
                              ImagePage(
                                heroImage: HeroImage(
                                  imageProvider: imageProvider,
                                  heroTag: heroTag,
                                ),
                              ),
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Hero(
                                  tag: heroTag,
                                  child: Image(
                                    image: imageProvider,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      stops: const [0.4, 1],
                                      colors: [
                                        Colors.transparent,
                                        theme.colorScheme.surface,
                                      ],
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: GlassMetrics.edgeInset,
                                  right: GlassMetrics.edgeInset,
                                  bottom: TappedSpacing.lg,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      GlassPill(
                                        label: booking.status.formattedName
                                            .toLowerCase(),
                                        icon: switch (booking.status) {
                                          BookingStatus.confirmed =>
                                            CupertinoIcons.checkmark_seal_fill,
                                          BookingStatus.pending =>
                                            CupertinoIcons.clock_fill,
                                          BookingStatus.canceled =>
                                            CupertinoIcons.xmark_circle_fill,
                                        },
                                        tint: switch (booking.status) {
                                          BookingStatus.confirmed =>
                                            TappedColors.success,
                                          BookingStatus.pending =>
                                            Colors.orange,
                                          BookingStatus.canceled =>
                                            TappedColors.error,
                                        },
                                      ),
                                      const SizedBox(height: TappedSpacing.sm),
                                      Text(
                                        booking.name.getOrElse(() => 'booking'),
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.displaySmall
                                            ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.8,
                                          height: 1.05,
                                        ),
                                      ),
                                      const SizedBox(height: TappedSpacing.xs),
                                      Text(
                                        '${dateFormat.format(booking.startTime)} · ${timeFormat.format(booking.startTime)}',
                                        style:
                                            theme.textTheme.bodyMedium?.copyWith(
                                          color: theme.colorScheme.onSurface
                                              .withValues(alpha: 0.7),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: FutureBuilder<Option<UserModel>>(
                          future: database.getUserById(booking.requesteeId),
                          builder: (context, snapshot) {
                            final requestee = snapshot.data;
                            return switch (requestee) {
                              null || None() => const SizedBox(
                                  height: 72,
                                  child: Center(child: GlassLoading()),
                                ),
                              Some(:final value) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: GlassMetrics.edgeInset,
                                    vertical: TappedSpacing.sm,
                                  ),
                                  child: GlassCard(
                                    padding: EdgeInsets.zero,
                                    child: UserTile(
                                      userId: value.id,
                                      user: Option.of(value),
                                      showFollowButton: false,
                                    ),
                                  ),
                                ),
                            };
                          },
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: GlassSection(
                          header: 'details',
                          children: [
                            switch (booking.requesterId) {
                              None() => const SizedBox.shrink(),
                              Some(:final value) =>
                                FutureBuilder<Option<UserModel>>(
                                  future: database.getUserById(value),
                                  builder: (context, snapshot) {
                                    final requester = snapshot.data;
                                    return switch (requester) {
                                      null || None() => const SizedBox.shrink(),
                                      Some(:final value) => GlassListTile(
                                          leading: UserAvatar(
                                            pushId: Option.of(value.id),
                                            pushUser: Option.of(value),
                                            imageUrl: value.profilePicture,
                                            radius: 16,
                                          ),
                                          title: 'booked by',
                                          value: value.displayName,
                                          onTap: () =>
                                              showCupertinoModalBottomSheet<
                                                  void>(
                                            context: context,
                                            backgroundColor: Colors.transparent,
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
                            switch (booking.location) {
                              None() => const SizedBox.shrink(),
                              Some(:final value) =>
                                FutureBuilder<Option<PlaceData>>(
                                  future: context.places
                                      .getPlaceById(value.placeId),
                                  builder: (context, snapshot) {
                                    final place = snapshot.data;
                                    return switch (place) {
                                      null || None() => const SizedBox.shrink(),
                                      Some(:final value) => GlassListTile(
                                          leadingIcon: CupertinoIcons.location_solid,
                                          leadingColor: TappedColors.error,
                                          title: 'location',
                                          subtitle: formattedFullAddress(
                                            value.addressComponents,
                                          ),
                                          trailing: Icon(
                                            CupertinoIcons.map,
                                            size: 18,
                                            color: theme.colorScheme.primary,
                                          ),
                                          onTap: () => MapsLauncher.launchQuery(
                                            value.shortFormattedAddress,
                                          ),
                                        ),
                                    };
                                  },
                                ),
                            },
                            GlassListTile(
                              leadingIcon: CupertinoIcons.calendar,
                              leadingColor: theme.colorScheme.primary,
                              title: 'date',
                              value: formattedDate,
                            ),
                            GlassListTile(
                              leadingIcon: CupertinoIcons.clock_fill,
                              leadingColor: Colors.orange,
                              title: 'time',
                              value: timeFormat.format(booking.startTime),
                            ),
                            if (isCurrentUserInvolved || isAdmin)
                              GlassListTile(
                                leadingIcon: CupertinoIcons.money_dollar_circle_fill,
                                leadingColor: TappedColors.success,
                                title: 'rate',
                                value:
                                    '\$${(booking.rate / 100).toStringAsFixed(2)}',
                              ),
                          ],
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: TappedSpacing.xl,
                            vertical: TappedSpacing.md,
                          ),
                          child: Text(
                            'to modify the booking, please contact '
                            'support@tapped.ai',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(
                        child: SizedBox(
                          height: GlassMetrics.bottomBarClearance + 60,
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    top: MediaQuery.paddingOf(context).top + TappedSpacing.sm,
                    left: GlassMetrics.edgeInset,
                    right: GlassMetrics.edgeInset,
                    child: Row(
                      children: [
                        GlassIconButton(
                          icon: CupertinoIcons.chevron_back,
                          variant: GlassVariant.clear,
                          semanticsLabel: 'back',
                          onPressed: () => context.pop(),
                        ),
                        const Spacer(),
                        if (isAdmin)
                          GlassIconButton(
                            icon: CupertinoIcons.ellipsis,
                            variant: GlassVariant.clear,
                            semanticsLabel: 'admin options',
                            onPressed: () {
                              final scaffoldMessenger =
                                  ScaffoldMessenger.of(context);
                              showGlassActionSheet(
                                context: context,
                                title: 'admin',
                                actions: [
                                  GlassAction(
                                    label: 'copy id · ${booking.id}',
                                    icon: CupertinoIcons.doc_on_doc,
                                    onPressed: () async {
                                      await Clipboard.setData(
                                        ClipboardData(text: booking.id),
                                      );
                                      scaffoldMessenger.showSnackBar(
                                        SnackBar(
                                          behavior: SnackBarBehavior.floating,
                                          backgroundColor:
                                              theme.colorScheme.primary,
                                          content: const Text(
                                            'booking id copied to clipboard',
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                  if (canConfirm || canCancel)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: GlassBottomBar(
                        child: Row(
                          children: [
                            if (canCancel)
                              Expanded(
                                child: GlassButton.destructive(
                                  label: 'cancel booking',
                                  onPressed: () async {
                                    final ok = await showGlassConfirm(
                                      context: context,
                                      title: 'cancel this booking?',
                                      message: 'the other party will be notified',
                                      confirmLabel: 'cancel booking',
                                      cancelLabel: 'keep it',
                                      destructive: true,
                                    );
                                    if (!ok || !context.mounted) return;
                                    final updated = booking.copyWith(
                                      status: BookingStatus.canceled,
                                    );
                                    await database.updateBooking(updated);
                                    onDeny?.call(updated);
                                    if (context.mounted) context.pop();
                                  },
                                ),
                              ),
                            if (canConfirm && canCancel)
                              const SizedBox(width: TappedSpacing.sm),
                            if (canConfirm)
                              Expanded(
                                child: GlassButton.primary(
                                  label: 'confirm booking',
                                  icon: CupertinoIcons.checkmark_alt,
                                  onPressed: () async {
                                    final updated = booking.copyWith(
                                      status: BookingStatus.confirmed,
                                    );
                                    await database.updateBooking(updated);
                                    onConfirm?.call(updated);
                                    if (context.mounted) context.pop();
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
