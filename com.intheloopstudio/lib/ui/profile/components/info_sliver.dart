import 'dart:ui';

import 'package:feedback/feedback.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/domains/models/performer_info.dart';
import 'package:intheloopapp/domains/models/social_following.dart';
import 'package:intheloopapp/domains/models/venue_info.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/profile/components/category_gauge.dart';
import 'package:intheloopapp/ui/profile/components/days_of_the_week_chart.dart';
import 'package:intheloopapp/ui/profile/profile_cubit.dart';
import 'package:intheloopapp/ui/share_profile/share_profile_view.dart';
import 'package:intheloopapp/utils/app_logger.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:intheloopapp/utils/current_user_builder.dart';
import 'package:intheloopapp/utils/custom_claims_builder.dart';
import 'package:intheloopapp/utils/geohash.dart';
import 'package:intheloopapp/utils/premium_builder.dart';
import 'package:intl/intl.dart';
import 'package:maps_launcher/maps_launcher.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:url_launcher/url_launcher.dart';

/// Grouped glass "details" and "contact" sections for a profile.
class InfoSliver extends StatelessWidget {
  const InfoSliver({super.key});

  Future<void> _copy(
    BuildContext context, {
    required bool isPremium,
    required String value,
    required String toast,
  }) async {
    if (!isPremium) {
      context.push(PaywallPage());
      return;
    }

    await Clipboard.setData(ClipboardData(text: value));
    await HapticFeedback.mediumImpact();
    await EasyLoading.showSuccess(
      toast,
      duration: const Duration(milliseconds: 500),
    );
  }

  Widget _locked(BuildContext context, String placeholder) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
      child: Text(
        placeholder,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        final user = state.visitedUser;
        final audience = user.socialFollowing.audienceSize;
        final performerInfo = user.performerInfo;
        final venueInfo = user.venueInfo;
        final bookerInfo = user.bookerInfo;
        final genres = performerInfo.map((t) => t.genres).getOrElse(
              () => venueInfo.map((t) => t.genres).getOrElse(() => []),
            );
        final rating = performerInfo.map((t) => t.rating).getOrElse(
              () => bookerInfo.map((t) => t.rating).getOrElse(
                    () => const None(),
                  ),
            );
        final averagePerformerTicketPrice =
            performerInfo.map((t) => t.formattedPriceRange);
        final averageAttendance = performerInfo
            .map(
              (t) => t.averageAttendance.fold(
                () => (audience / 250).round(),
                (attendance) => attendance,
              ),
            )
            .getOrElse(() => 0);
        final label = performerInfo.map((t) => t.label).getOrElse(() => 'None');
        final bookingAgency = performerInfo.flatMap((t) => t.bookingAgency);
        final currPlace = state.place;
        final idealPerformerProfile =
            venueInfo.flatMap((t) => t.idealPerformerProfile);
        final bookingEmail =
            venueInfo.flatMap((t) => t.bookingEmail).toNullable();
        final phone = user.phoneNumber.toNullable();
        final capacity = venueInfo.flatMap((t) => t.capacity).toNullable();
        final formatted = NumberFormat.compactLong();
        final compact = NumberFormat.compactCurrency(
          decimalDigits: 0,
          symbol: '',
        );

        return CurrentUserBuilder(
          builder: (context, currentUser) {
            return CustomClaimsBuilder(
              builder: (context, claims) {
                return PremiumBuilder(
                  builder: (context, isPremium) {
                    final details = <Widget>[
                      if (currPlace case Some(:final value))
                        GlassListTile(
                          leadingIcon: CupertinoIcons.location_solid,
                          title: formattedShortAddress(
                            value.addressComponents,
                          ).toLowerCase(),
                          trailing: Icon(
                            CupertinoIcons.map,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          onTap: () => MapsLauncher.launchQuery(
                            value.shortFormattedAddress,
                          ),
                        ),
                      if (capacity != null)
                        GlassListTile(
                          leadingIcon: CupertinoIcons.person_3_fill,
                          title: 'capacity',
                          value: formatted.format(capacity),
                        ),
                      if (genres.isNotEmpty)
                        GlassListTile(
                          leadingIcon: CupertinoIcons.music_note_2,
                          title: 'genres',
                          subtitle:
                              genres.map((e) => e.toLowerCase()).join(', '),
                        ),
                      if (performerInfo.isSome())
                        GlassListTile(
                          leadingIcon: CupertinoIcons.person_2_fill,
                          title: 'followers',
                          value: compact.format(audience),
                        ),
                      if (averagePerformerTicketPrice case Some(:final value))
                        GlassListTile(
                          leadingIcon: CupertinoIcons.money_dollar_circle,
                          title: 'avg. ticket price',
                          trailing: isPremium
                              ? Text(value, style: theme.textTheme.bodyLarge)
                              : _locked(context, r'$??'),
                          onTap: isPremium
                              ? null
                              : () => context.push(PaywallPage()),
                        ),
                      if (venueInfo.isNone() && averageAttendance > 0)
                        GlassListTile(
                          leadingIcon: CupertinoIcons.chart_bar_alt_fill,
                          title: 'avg. attendance',
                          trailing: isPremium
                              ? Text(
                                  formatted.format(averageAttendance),
                                  style: theme.textTheme.bodyLarge,
                                )
                              : _locked(context, '???'),
                          onTap: isPremium
                              ? null
                              : () => context.push(PaywallPage()),
                        ),
                      if (label != 'None')
                        GlassListTile(
                          leadingIcon: CupertinoIcons.tag_fill,
                          title: 'label',
                          value: label.toLowerCase(),
                        ),
                      if (bookingAgency case Some(:final value))
                        GlassListTile(
                          leadingIcon: CupertinoIcons.briefcase_fill,
                          title: 'booking agency',
                          value: value,
                        ),
                      if (rating case Some(:final value))
                        GlassListTile(
                          leadingIcon: CupertinoIcons.star_circle_fill,
                          title: 'rating',
                          trailing: RatingBarIndicator(
                            rating: value,
                            itemBuilder: (context, index) => const Icon(
                              CupertinoIcons.star_fill,
                              color: Colors.amber,
                            ),
                            itemSize: 18,
                          ),
                        ),
                      if (performerInfo case Some(:final value))
                        GlassListTile(
                          leadingIcon: CupertinoIcons.doc_person_fill,
                          title: 'press kit',
                          showChevron: true,
                          onTap: switch (value.pressKitUrl) {
                            None() => () => showCupertinoModalBottomSheet<void>(
                                  context: context,
                                  backgroundColor: Colors.transparent,
                                  builder: (context) => ShareProfileView(
                                    userId: user.id,
                                    user: Option.of(user),
                                  ),
                                ),
                            Some(:final value) => () =>
                                launchUrl(Uri.parse(value)),
                          },
                        ),
                      if (idealPerformerProfile case Some(:final value))
                        GlassListTile(
                          leadingIcon: CupertinoIcons.sparkles,
                          title: 'who they book',
                          showChevron: true,
                          onTap: () {
                            FirebaseAnalytics.instance.logEvent(
                              name: 'ideal_performer_profile',
                              parameters: {
                                'venue_id': user.id,
                                'is_premium': isPremium,
                              },
                            );

                            if (!isPremium) {
                              context.push(PaywallPage());
                              return;
                            }

                            showGlassSheet<void>(
                              context: context,
                              title: 'who they normally book',
                              scrollable: true,
                              builder: (context) => Text(
                                value,
                                style: theme.textTheme.bodyLarge
                                    ?.copyWith(height: 1.45),
                              ),
                            );
                          },
                        ),
                    ];

                    final contact = <Widget>[
                      if (bookingEmail != null)
                        GlassListTile(
                          leadingIcon: CupertinoIcons.envelope_fill,
                          title: 'booking email',
                          subtitle:
                              isPremium ? bookingEmail : '•••••@email.com',
                          trailing: Icon(
                            isPremium
                                ? CupertinoIcons.doc_on_doc
                                : CupertinoIcons.lock_fill,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          onTap: () => _copy(
                            context,
                            isPremium: isPremium,
                            value: bookingEmail,
                            toast: 'copied email',
                          ),
                        ),
                      if (phone != null)
                        GlassListTile(
                          leadingIcon: CupertinoIcons.phone_fill,
                          title: 'phone',
                          subtitle: isPremium ? phone : '•••-•••-••••',
                          trailing: Icon(
                            isPremium
                                ? CupertinoIcons.doc_on_doc
                                : CupertinoIcons.lock_fill,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          onTap: () => _copy(
                            context,
                            isPremium: isPremium,
                            value: phone,
                            toast: 'copied phone',
                          ),
                        ),
                    ];

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (details.isNotEmpty)
                          GlassSection(
                            header: 'details',
                            children: details,
                          ),
                        if (contact.isNotEmpty)
                          GlassSection(
                            header: 'contact',
                            footer: isPremium
                                ? null
                                : 'upgrade to tapped premium to unlock '
                                    'contact details',
                            children: contact,
                          ),
                        if (venueInfo.isSome() && user.unclaimed)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: GlassMetrics.edgeInset,
                            ),
                            child: GlassButton.plain(
                              label: 'something incorrect? let us know',
                              icon: CupertinoIcons.exclamationmark_bubble,
                              compact: true,
                              onPressed: () =>
                                  _reportIncorrect(context, currentUser.id),
                            ),
                          ),
                        const CategoryGauge(),
                        const DaysOfTheWeekChart(),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  void _reportIncorrect(BuildContext context, String currentUserId) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final storage = context.storage;
    final database = context.database;

    HapticFeedback.lightImpact();
    BetterFeedback.of(context).show((UserFeedback feedback) {
      try {
        logger.debug(
          'feedback: ${feedback.text} and ${feedback.extra}',
        );

        storage
            .uploadFeedbackScreenshot(
          currentUserId,
          feedback.screenshot,
        )
            .then((imageUrl) {
          database.sendFeedback(
            currentUserId,
            feedback,
            imageUrl,
          );
        });

        scaffoldMessenger.showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green,
            content: Text('feedback sent'),
          ),
        );
      } catch (error, stackTrace) {
        logger.error(
          'error sending feedback',
          error: error,
          stackTrace: stackTrace,
        );
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
            content: Text('error sending feedback'),
          ),
        );
      }
    });
  }
}
